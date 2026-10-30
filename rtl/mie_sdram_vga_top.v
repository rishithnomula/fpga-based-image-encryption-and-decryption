// -----------------------------------------------------------------------------
// Top-level DE2-115 design: MIE encryption/decryption of two SDRAM-backed images.
//
// KEY0 : reset
// KEY1 : encrypt Image 1 and Image 2; encrypted results are written to SDRAM
//        and then copied from SDRAM into the encrypted VGA cache.
// KEY2 : decrypt both encrypted images; decrypted results are written to SDRAM
//        and then copied from SDRAM into the encrypted VGA cache.
//
// VGA phases:
//   before KEY1 : Image 1 | Image 2
//   after KEY1  : Original | Encrypted for each image
//   after KEY2  : Original | Encrypted | Decrypted for each image
// -----------------------------------------------------------------------------
module mie_sdram_vga_top #(
    parameter CA_WIDTH = 4593,
    parameter INIT_FILE = "images2.mif",
    parameter IMAGE_WIDTH = 112,
    parameter IMAGE_HEIGHT = 144
)(
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [17:0] SW,
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,

    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_CLK,
    output wire        VGA_BLANK_N,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_SYNC_N,

    output wire [12:0] DRAM_ADDR,
    output wire [1:0]  DRAM_BA,
    output wire        DRAM_CS_N,
    output wire        DRAM_RAS_N,
    output wire        DRAM_CAS_N,
    output wire        DRAM_WE_N,
    output wire        DRAM_CKE,
    output wire        DRAM_CLK,
    inout  wire [31:0] DRAM_DQ,
    output wire [3:0]  DRAM_DQM
);
    localparam integer IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer TOTAL_PIXELS = 2 * IMAGE_PIXELS;

    // ---------------- reset and push-button synchronization ----------------
    reg [2:0] reset_pipe;
    reg [1:0] key1_sync, key2_sync;
    reg key1_prev, key2_prev;

    // KEY0 is active-low. Assert reset asynchronously and release it through
    // three CLOCK_50 stages. The other active-low keys are synchronised too.
    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) begin
            reset_pipe <= 3'b000;
            key1_sync  <= 2'b11;
            key2_sync  <= 2'b11;
            key1_prev  <= 1'b1;
            key2_prev  <= 1'b1;
        end else begin
            reset_pipe <= {reset_pipe[1:0], 1'b1};
            key1_sync  <= {key1_sync[0], KEY[1]};
            key2_sync  <= {key2_sync[0], KEY[2]};
            key1_prev  <= key1_sync[1];
            key2_prev  <= key2_sync[1];
        end
    end
    wire rst_n = reset_pipe[2];
    wire key1_press = key1_prev && !key1_sync[1];
    wire key2_press = key2_prev && !key2_sync[1];

    // ---------------- MIE core (unchanged verified encryption datapath) -----
    wire core_ready, core_busy, core_done, selftest_done, selftest_pass;
    wire core_cmd_start, core_cmd_decrypt, core_in_wr_en;
    wire [7:0] core_in_wr_addr, core_in_wr_data, core_out_rd_addr, core_out_rd_data;

    mie_core #(.CA_WIDTH(CA_WIDTH)) u_mie_core (
        .clk(CLOCK_50), .rst_n(rst_n),
        .ready(core_ready), .busy(core_busy), .done(core_done),
        .selftest_done(selftest_done), .selftest_pass(selftest_pass),
        .cmd_start(core_cmd_start), .cmd_decrypt(core_cmd_decrypt),
        .in_wr_en(core_in_wr_en), .in_wr_addr(core_in_wr_addr), .in_wr_data(core_in_wr_data),
        .out_rd_addr(core_out_rd_addr), .out_rd_data(core_out_rd_data)
    );

    // ---------------- external SDRAM image loader ---------------------------
    wire sdram_init_done;
    wire loader_req_valid, loader_req_ready, loader_req_write;
    wire [24:0] loader_req_addr;
    wire [31:0] loader_req_wdata;
    wire [3:0] loader_req_dqm;
    wire loader_rsp_valid, load_done;
    wire [31:0] ctrl_rsp_data;
    wire [14:0] vga_ra;
    wire [23:0] rd_plain;

    sdram_image_loader #(
        .INIT_FILE(INIT_FILE), .PIXELS(TOTAL_PIXELS), .ADDR_WIDTH(15)
    ) u_loader (
        .clk(CLOCK_50), .rst_n(rst_n), .sdram_ready(sdram_init_done),
        .req_valid(loader_req_valid), .req_ready(loader_req_ready),
        .req_write(loader_req_write), .req_addr(loader_req_addr),
        .req_wdata(loader_req_wdata), .req_dqm(loader_req_dqm),
        .rsp_valid(loader_rsp_valid), .rsp_rdata(ctrl_rsp_data),
        .vga_addr(vga_ra), .vga_data(rd_plain), .done(load_done)
    );

    // ---------------- SDRAM-backed MIE engine -------------------------------
    wire engine_busy, encrypt_done, decrypt_done;
    wire engine_req_valid, engine_req_ready, engine_req_write;
    wire [24:0] engine_req_addr;
    wire [31:0] engine_req_wdata;
    wire [3:0] engine_req_dqm;
    wire engine_rsp_valid;
    wire [31:0] engine_rsp_data;
    wire [7:0] debug_block;
    reg start_encrypt, start_decrypt;

    mie_sdram_engine #(
        .LOG2_IMG(6), .IMAGE_COUNT(2),
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) u_engine (
        .clk(CLOCK_50), .rst_n(rst_n),
        .start_encrypt(start_encrypt), .start_decrypt(start_decrypt),
        .busy(engine_busy), .encrypt_done(encrypt_done), .decrypt_done(decrypt_done),
        .core_ready(core_ready), .core_busy(core_busy), .core_done(core_done),
        .cmd_start(core_cmd_start), .cmd_decrypt(core_cmd_decrypt),
        .in_wr_en(core_in_wr_en), .in_wr_addr(core_in_wr_addr), .in_wr_data(core_in_wr_data),
        .out_rd_addr(core_out_rd_addr), .out_rd_data(core_out_rd_data),
        .mem_req_valid(engine_req_valid), .mem_req_ready(engine_req_ready),
        .mem_req_write(engine_req_write), .mem_req_addr(engine_req_addr),
        .mem_req_wdata(engine_req_wdata), .mem_req_dqm(engine_req_dqm),
        .mem_rsp_valid(engine_rsp_valid), .mem_rsp_data(engine_rsp_data),
        .debug_block(debug_block)
    );

    // ---------------- SDRAM -> VGA cache DMA --------------------------------
    reg dma_start;
    reg [24:0] dma_source_base;
    reg [1:0] dma_target; // 1 = encrypted cache, 2 = decrypted cache
    wire dma_busy, dma_done;
    wire dma_req_valid, dma_req_ready, dma_req_write;
    wire [24:0] dma_req_addr;
    wire [31:0] dma_req_wdata;
    wire [3:0] dma_req_dqm;
    wire dma_rsp_valid;
    wire [31:0] dma_rsp_data;
    wire dma_cache_we;
    wire [14:0] dma_cache_addr;
    wire [23:0] dma_cache_data;

    sdram_cache_dma #(.PIXELS(TOTAL_PIXELS), .ADDR_WIDTH(15)) u_cache_dma (
        .clk(CLOCK_50), .rst_n(rst_n), .start(dma_start),
        .source_base(dma_source_base), .busy(dma_busy), .done(dma_done),
        .mem_req_valid(dma_req_valid), .mem_req_ready(dma_req_ready),
        .mem_req_write(dma_req_write), .mem_req_addr(dma_req_addr),
        .mem_req_wdata(dma_req_wdata), .mem_req_dqm(dma_req_dqm),
        .mem_rsp_valid(dma_rsp_valid), .mem_rsp_data(dma_rsp_data),
        .cache_we(dma_cache_we), .cache_addr(dma_cache_addr), .cache_data(dma_cache_data)
    );

    // ---------------- single-owner SDRAM request mux ------------------------
    // Loading is exclusive at startup. Afterwards the engine and cache DMA are
    // mutually exclusive by the flow controller below.
    reg [1:0] response_owner; // 0 loader, 1 engine, 2 cache DMA
    wire select_loader = !load_done;
    wire select_dma = load_done && dma_busy;
    wire select_engine = load_done && !dma_busy && engine_req_valid;

    wire ctrl_req_valid = select_loader ? loader_req_valid :
                          select_dma ? dma_req_valid :
                          select_engine ? engine_req_valid : 1'b0;
    wire ctrl_req_write = select_loader ? loader_req_write :
                          select_dma ? dma_req_write : engine_req_write;
    wire [24:0] ctrl_req_addr = select_loader ? loader_req_addr :
                                select_dma ? dma_req_addr : engine_req_addr;
    wire [31:0] ctrl_req_wdata = select_loader ? loader_req_wdata :
                                 select_dma ? dma_req_wdata : engine_req_wdata;
    wire [3:0] ctrl_req_dqm = select_loader ? loader_req_dqm :
                              select_dma ? dma_req_dqm : engine_req_dqm;
    wire ctrl_req_ready, ctrl_rsp_valid;

    assign loader_req_ready = select_loader && ctrl_req_ready;
    assign dma_req_ready = select_dma && ctrl_req_ready;
    assign engine_req_ready = select_engine && ctrl_req_ready;
    assign loader_rsp_valid = ctrl_rsp_valid && (response_owner == 2'd0);
    assign engine_rsp_valid = ctrl_rsp_valid && (response_owner == 2'd1);
    assign engine_rsp_data = ctrl_rsp_data;
    assign dma_rsp_valid = ctrl_rsp_valid && (response_owner == 2'd2);
    assign dma_rsp_data = ctrl_rsp_data;

    always @(posedge CLOCK_50) begin
        if (!rst_n) response_owner <= 2'd0;
        else if (ctrl_req_valid && ctrl_req_ready) begin
            if (select_loader) response_owner <= 2'd0;
            else if (select_dma) response_owner <= 2'd2;
            else response_owner <= 2'd1;
        end
    end

    sdram_ctrl32 u_sdram (
        .clk(CLOCK_50), .rst_n(rst_n),
        .req_valid(ctrl_req_valid), .req_ready(ctrl_req_ready),
        .req_write(ctrl_req_write), .req_addr(ctrl_req_addr),
        .req_wdata(ctrl_req_wdata), .req_dqm(ctrl_req_dqm),
        .rsp_valid(ctrl_rsp_valid), .rsp_rdata(ctrl_rsp_data),
        .init_done(sdram_init_done),
        .DRAM_ADDR(DRAM_ADDR), .DRAM_BA(DRAM_BA),
        .DRAM_CS_N(DRAM_CS_N), .DRAM_RAS_N(DRAM_RAS_N),
        .DRAM_CAS_N(DRAM_CAS_N), .DRAM_WE_N(DRAM_WE_N),
        .DRAM_CKE(DRAM_CKE), .DRAM_CLK(DRAM_CLK),
        .DRAM_DQ(DRAM_DQ), .DRAM_DQM(DRAM_DQM)
    );

    // ---------------- high-level KEY1 / KEY2 operation sequencer -------------
    localparam FLOW_WAIT_LOAD = 3'd0,
               FLOW_IDLE      = 3'd1,
               FLOW_ENCRYPT   = 3'd2,
               FLOW_CIPHER_DMA= 3'd3,
               FLOW_DECRYPT   = 3'd4,
               FLOW_DEC_DMA   = 3'd5;
    reg [2:0] flow_state;
    reg [1:0] display_phase;
    reg cipher_valid, decrypted_valid;

    always @(posedge CLOCK_50) begin
        if (!rst_n) begin
            flow_state <= FLOW_WAIT_LOAD;
            display_phase <= 2'd0;
            cipher_valid <= 1'b0;
            decrypted_valid <= 1'b0;
            start_encrypt <= 1'b0;
            start_decrypt <= 1'b0;
            dma_start <= 1'b0;
            dma_source_base <= 25'd32256;
            dma_target <= 2'd0;
        end else begin
            start_encrypt <= 1'b0;
            start_decrypt <= 1'b0;
            dma_start <= 1'b0;

            case (flow_state)
                FLOW_WAIT_LOAD: begin
                    if (load_done && core_ready) flow_state <= FLOW_IDLE;
                end
                FLOW_IDLE: begin
                    if (key1_press && load_done && core_ready) begin
                        start_encrypt <= 1'b1;
                        flow_state <= FLOW_ENCRYPT;
                        cipher_valid <= 1'b0;
                        decrypted_valid <= 1'b0;
                        display_phase <= 2'd0;
                    end else if (key2_press && load_done && core_ready && cipher_valid) begin
                        start_decrypt <= 1'b1;
                        flow_state <= FLOW_DECRYPT;
                        decrypted_valid <= 1'b0;
                        display_phase <= 2'd1;
                    end
                end
                FLOW_ENCRYPT: begin
                    if (encrypt_done) begin
                        dma_source_base <= 25'd32256;
                        dma_target <= 2'd1;
                        dma_start <= 1'b1;
                        flow_state <= FLOW_CIPHER_DMA;
                    end
                end
                FLOW_CIPHER_DMA: begin
                    if (dma_done) begin
                        cipher_valid <= 1'b1;
                        display_phase <= 2'd1;
                        flow_state <= FLOW_IDLE;
                    end
                end
                FLOW_DECRYPT: begin
                    if (decrypt_done) begin
                        dma_source_base <= 25'd64512;
                        dma_target <= 2'd2;
                        dma_start <= 1'b1;
                        flow_state <= FLOW_DEC_DMA;
                    end
                end
                FLOW_DEC_DMA: begin
                    if (dma_done) begin
                        decrypted_valid <= 1'b1;
                        display_phase <= 2'd2;
                        flow_state <= FLOW_IDLE;
                    end
                end
                default: flow_state <= FLOW_WAIT_LOAD;
            endcase
        end
    end

    // ---------------- result caches used only by the VGA scanout ------------
    wire [23:0] rd_cipher, rd_dec;
    wire cipher_cache_we = dma_cache_we && (dma_target == 2'd1);
    wire dec_cache_we = dma_cache_we && (dma_target == 2'd2);

    // The loader's M9K image memory is reused as the original-image VGA cache
    // after SDRAM readback, avoiding a second full-frame on-chip copy.
    ram24 #(.AW(15)) m_cipher_cache (
        .clk(CLOCK_50), .we(cipher_cache_we), .wa(dma_cache_addr), .wd(dma_cache_data),
        .ra(vga_ra), .rd(rd_cipher)
    );
    ram24 #(.AW(15)) m_dec_cache (
        .clk(CLOCK_50), .we(dec_cache_we), .wa(dma_cache_addr), .wd(dma_cache_data),
        .ra(vga_ra), .rd(rd_dec)
    );

    img_display_2img u_display (
        .clk(CLOCK_50), .rst_n(rst_n), .phase(display_phase), .rd_addr(vga_ra),
        .rd_plain(rd_plain), .rd_cipher(rd_cipher), .rd_dec(rd_dec),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_CLK(VGA_CLK), .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_SYNC_N(VGA_SYNC_N)
    );

    // LEDs: SDRAM init, image load, core ready, processing busy, encrypted,
    // decrypted, self-test complete, self-test pass, self-test fail.
    assign LEDG[0] = sdram_init_done;
    assign LEDG[1] = load_done;
    assign LEDG[2] = core_ready;
    assign LEDG[3] = engine_busy || dma_busy;
    assign LEDG[4] = cipher_valid;
    assign LEDG[5] = decrypted_valid;
    assign LEDG[6] = selftest_done;
    assign LEDG[7] = selftest_done && selftest_pass;
    assign LEDG[8] = selftest_done && !selftest_pass;

    assign LEDR = {2'd0, debug_block, display_phase, flow_state, 3'b000};
    // SW remains on the board-level interface for pin compatibility; it is unused.
endmodule
