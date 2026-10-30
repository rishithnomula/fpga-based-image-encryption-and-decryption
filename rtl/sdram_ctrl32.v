// -----------------------------------------------------------------------------
// DE2-115 external SDRAM controller, 32-bit data path.
//
// The two board SDRAM devices share address/control and form a 32-bit bus.
// One 32-bit word is addressed per request.  DQM is active-high byte masking.
//
// Timing assumes CLOCK_50 = 50 MHz and the board's SDRAM devices can operate
// with conservative 2-cycle tRP/tRCD and 7-cycle tRFC/tRAS recovery values.
// READ uses CAS latency 2, burst length 1, auto-precharge.
// -----------------------------------------------------------------------------
module sdram_ctrl32 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req_valid,
    output wire        req_ready,
    input  wire        req_write,
    input  wire [24:0] req_addr,       // 32-bit word address
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_dqm,        // 1 = mask byte lane

    output reg         rsp_valid,
    output reg  [31:0] rsp_rdata,
    output reg         init_done,

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
    localparam [4:0]
        ST_POWERUP    = 5'd0,
        ST_PRECHARGE  = 5'd1,
        ST_PRE_WAIT   = 5'd2,
        ST_REFRESH1   = 5'd3,
        ST_REF1_WAIT  = 5'd4,
        ST_REFRESH2   = 5'd5,
        ST_REF2_WAIT  = 5'd6,
        ST_MODE       = 5'd7,
        ST_MODE_WAIT  = 5'd8,
        ST_IDLE       = 5'd9,
        ST_ACTIVATE   = 5'd10,
        ST_RCD_WAIT   = 5'd11,
        ST_READ       = 5'd12,
        ST_READ_W1    = 5'd13,
        ST_READ_W2    = 5'd14,
        ST_READ_CAP   = 5'd15,
        ST_READ_REC   = 5'd16,
        ST_WRITE      = 5'd17,
        ST_WRITE_REC  = 5'd18,
        ST_REFRESH    = 5'd19,
        ST_REF_WAIT   = 5'd20;

    reg [4:0] state;
    reg [15:0] timer;
    reg [8:0] refresh_timer;
    reg refresh_due;

    reg [24:0] addr_latched;
    reg [31:0] wdata_latched;
    reg [3:0]  dqm_latched;
    reg        write_latched;

    reg [12:0] dram_addr_r;
    reg [1:0]  dram_ba_r;
    reg        dram_cs_n_r, dram_ras_n_r, dram_cas_n_r, dram_we_n_r;
    reg [3:0]  dram_dqm_r;
    reg        dq_oe;

    assign DRAM_ADDR = dram_addr_r;
    assign DRAM_BA   = dram_ba_r;
    assign DRAM_CS_N = dram_cs_n_r;
    assign DRAM_RAS_N = dram_ras_n_r;
    assign DRAM_CAS_N = dram_cas_n_r;
    assign DRAM_WE_N = dram_we_n_r;
    assign DRAM_DQM = dram_dqm_r;
    assign DRAM_CKE = 1'b1;
    // The DE2-115 SDRAM clock is driven from the board's 50 MHz oscillator.
    // A board-level PLL phase shift may be added if timing analysis requires it.
    assign DRAM_CLK = clk;
    assign DRAM_DQ = dq_oe ? wdata_latched : 32'bz;

    assign req_ready = init_done && (state == ST_IDLE) && !refresh_due;

    // SDRAM command and data pins are driven combinationally from the state so
    // command/address/data are stable before the active SDRAM clock edge.
    always @* begin
        dram_addr_r  = 13'd0;
        dram_ba_r    = addr_latched[11:10];
        dram_cs_n_r  = 1'b0;
        dram_ras_n_r = 1'b1;
        dram_cas_n_r = 1'b1;
        dram_we_n_r  = 1'b1;
        dram_dqm_r   = 4'b1111;
        dq_oe        = 1'b0;
        case (state)
            ST_PRECHARGE: begin
                dram_ras_n_r = 1'b0;
                dram_we_n_r  = 1'b0;
                dram_addr_r  = 13'h400; // A10=1: precharge all banks
            end
            ST_REFRESH1, ST_REFRESH2, ST_REFRESH: begin
                dram_ras_n_r = 1'b0;
                dram_cas_n_r = 1'b0;
            end
            ST_MODE: begin
                dram_ras_n_r = 1'b0;
                dram_cas_n_r = 1'b0;
                dram_we_n_r  = 1'b0;
                dram_addr_r  = 13'h220; // BL=1, sequential, CL=2, single write
                dram_ba_r    = 2'b00;
            end
            ST_ACTIVATE: begin
                dram_ras_n_r = 1'b0;
                dram_addr_r  = addr_latched[24:12];
                dram_ba_r    = addr_latched[11:10];
            end
            ST_READ: begin
                dram_cas_n_r = 1'b0;
                dram_addr_r  = {2'b00, 1'b1, addr_latched[9:0]}; // A10=1 auto-precharge
                dram_ba_r    = addr_latched[11:10];
                dram_dqm_r   = 4'b0000;
            end
            ST_READ_W1, ST_READ_W2, ST_READ_CAP: begin
                // DQM is pipelined by CL=2 for reads; keep all byte lanes open
                // until after the return data has been captured.
                dram_dqm_r = 4'b0000;
            end
            ST_WRITE: begin
                dram_cas_n_r = 1'b0;
                dram_we_n_r  = 1'b0;
                dram_addr_r  = {2'b00, 1'b1, addr_latched[9:0]}; // A10=1 auto-precharge
                dram_ba_r    = addr_latched[11:10];
                dram_dqm_r   = dqm_latched;
                dq_oe        = 1'b1;
            end
            default: begin end // NOP
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state          <= ST_POWERUP;
            timer          <= 16'd0;
            refresh_timer  <= 9'd0;
            refresh_due    <= 1'b0;
            init_done      <= 1'b0;
            rsp_valid      <= 1'b0;
            rsp_rdata      <= 32'd0;
            addr_latched   <= 25'd0;
            wdata_latched  <= 32'd0;
            dqm_latched    <= 4'b1111;
            write_latched  <= 1'b0;
        end else begin
            rsp_valid <= 1'b0;

            if (init_done && !refresh_due) begin
                if (refresh_timer >= 9'd349)
                    refresh_due <= 1'b1;
                else
                    refresh_timer <= refresh_timer + 1'b1;
            end

            case (state)
                // 200 us power-up wait at 50 MHz.
                ST_POWERUP: begin
                    if (timer == 16'd9999) begin timer <= 0; state <= ST_PRECHARGE; end
                    else timer <= timer + 1'b1;
                end
                ST_PRECHARGE: begin timer <= 0; state <= ST_PRE_WAIT; end
                ST_PRE_WAIT: begin
                    if (timer == 16'd2) begin timer <= 0; state <= ST_REFRESH1; end
                    else timer <= timer + 1'b1;
                end
                ST_REFRESH1: begin timer <= 0; state <= ST_REF1_WAIT; end
                ST_REF1_WAIT: begin
                    if (timer == 16'd7) begin timer <= 0; state <= ST_REFRESH2; end
                    else timer <= timer + 1'b1;
                end
                ST_REFRESH2: begin timer <= 0; state <= ST_REF2_WAIT; end
                ST_REF2_WAIT: begin
                    if (timer == 16'd7) begin timer <= 0; state <= ST_MODE; end
                    else timer <= timer + 1'b1;
                end
                ST_MODE: begin timer <= 0; state <= ST_MODE_WAIT; end
                ST_MODE_WAIT: begin
                    if (timer == 16'd2) begin
                        timer <= 0;
                        init_done <= 1'b1;
                        refresh_timer <= 0;
                        state <= ST_IDLE;
                    end else timer <= timer + 1'b1;
                end

                ST_IDLE: begin
                    if (refresh_due) begin
                        timer <= 0;
                        state <= ST_REFRESH;
                    end else if (req_valid) begin
                        addr_latched  <= req_addr;
                        wdata_latched <= req_wdata;
                        dqm_latched   <= req_dqm;
                        write_latched <= req_write;
                        state <= ST_ACTIVATE;
                    end
                end
                ST_ACTIVATE: begin timer <= 0; state <= ST_RCD_WAIT; end
                ST_RCD_WAIT: begin
                    if (timer == 16'd2) begin
                        timer <= 0;
                        state <= write_latched ? ST_WRITE : ST_READ;
                    end else timer <= timer + 1'b1;
                end
                ST_READ:   state <= ST_READ_W1;
                ST_READ_W1: state <= ST_READ_W2;
                ST_READ_W2: state <= ST_READ_CAP;
                ST_READ_CAP: begin
                    rsp_rdata <= DRAM_DQ;
                    rsp_valid <= 1'b1;
                    timer <= 0;
                    state <= ST_READ_REC;
                end
                ST_READ_REC: begin
                    if (timer == 16'd4) begin timer <= 0; state <= ST_IDLE; end
                    else timer <= timer + 1'b1;
                end
                ST_WRITE: begin timer <= 0; state <= ST_WRITE_REC; end
                ST_WRITE_REC: begin
                    if (timer == 16'd7) begin
                        timer <= 0;
                        rsp_valid <= 1'b1;
                        state <= ST_IDLE;
                    end else timer <= timer + 1'b1;
                end
                ST_REFRESH: begin timer <= 0; state <= ST_REF_WAIT; end
                ST_REF_WAIT: begin
                    if (timer == 16'd7) begin
                        timer <= 0;
                        refresh_timer <= 0;
                        refresh_due <= 1'b0;
                        state <= ST_IDLE;
                    end else timer <= timer + 1'b1;
                end
                default: begin state <= ST_POWERUP; timer <= 0; init_done <= 1'b0; end
            endcase
        end
    end
endmodule
