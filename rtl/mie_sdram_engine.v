// -----------------------------------------------------------------------------
// MIE image engine backed by external SDRAM.
// Two 112x144 RGB images are stored as one 32-bit word per pixel:
//   [31:24] unused, [23:16] R, [15:8] G, [7:0] B.
// SDRAM word regions (32-bit word addresses): original 0..32255,
// encrypted 32256..64511, decrypted 64512..96767.
//
// The MIE core still works on 256-byte blocks. The engine streams RGB bytes
// from SDRAM and writes complete RGB pixels back. It retains only one cached
// input pixel and the partial output R/G bytes between core blocks.
// -----------------------------------------------------------------------------
module mie_sdram_engine #(
    parameter LOG2_IMG = 6,       // retained for compatibility with older instantiations
    parameter IMAGE_COUNT = 2,
    parameter IMAGE_WIDTH = 112,
    parameter IMAGE_HEIGHT = 144
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_encrypt,
    input  wire        start_decrypt,
    output wire        busy,
    output reg         encrypt_done,
    output reg         decrypt_done,

    input  wire        core_ready,
    input  wire        core_busy,
    input  wire        core_done,
    output reg         cmd_start,
    output reg         cmd_decrypt,
    output reg         in_wr_en,
    output reg  [7:0]  in_wr_addr,
    output reg  [7:0]  in_wr_data,
    output reg  [7:0]  out_rd_addr,
    input  wire [7:0]  out_rd_data,

    output wire        mem_req_valid,
    input  wire        mem_req_ready,
    output wire        mem_req_write,
    output wire [24:0] mem_req_addr,
    output wire [31:0] mem_req_wdata,
    output wire [3:0]  mem_req_dqm,
    input  wire        mem_rsp_valid,
    input  wire [31:0] mem_rsp_data,
    output wire [7:0]  debug_block
);
    localparam integer PIXELS_PER_IMAGE = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer BYTES_PER_IMAGE = PIXELS_PER_IMAGE * 3;
    localparam integer BLOCKS_PER_IMAGE = BYTES_PER_IMAGE / 256;
    localparam [24:0] ORIGINAL_BASE = 25'd0;
    localparam [24:0] CIPHER_BASE   = IMAGE_COUNT * PIXELS_PER_IMAGE;
    localparam [24:0] DECRYPT_BASE  = 2 * IMAGE_COUNT * PIXELS_PER_IMAGE;

    localparam [4:0]
        S_IDLE       = 5'd0,
        S_BLOCK      = 5'd1,
        S_IN_PREP    = 5'd2,
        S_IN_REQ     = 5'd3,
        S_IN_WAIT    = 5'd4,
        S_IN_PUSH    = 5'd5,
        S_CMD        = 5'd6,
        S_CMD_GAP    = 5'd7,
        S_WAIT_CLEAR = 5'd8,
        S_WAIT_DONE  = 5'd9,
        S_OUT_ADDR   = 5'd10,
        S_OUT_LATCH  = 5'd11,
        S_OUT_REQ    = 5'd12,
        S_OUT_WAIT   = 5'd13,
        S_BLOCK_NEXT = 5'd14;

    reg [4:0] state;
    reg decrypt_mode;
    reg [1:0] image_no;
    reg [7:0] block_no;
    reg [7:0] byte_no;

    // Current stream cursor, in RGB pixels plus channel 0=R, 1=G, 2=B.
    reg [13:0] in_pixel;
    reg [1:0]  in_channel;
    reg [13:0] block_pixel;
    reg [1:0]  block_channel;

    reg [13:0] out_pixel;
    reg [1:0]  out_channel;
    reg [31:0] pixel_cache;
    reg [13:0] cache_pixel;
    reg        cache_valid;
    reg [7:0]  byte_hold;
    reg [7:0]  output_byte;
    reg [7:0]  red_hold;
    reg [7:0]  green_hold;

    wire [24:0] image_offset = (image_no == 2'd0) ? 25'd0 : PIXELS_PER_IMAGE;
    wire [24:0] source_base = decrypt_mode ? CIPHER_BASE : ORIGINAL_BASE;
    wire [24:0] target_base = decrypt_mode ? DECRYPT_BASE : CIPHER_BASE;
    wire [24:0] in_word_addr = source_base + image_offset + in_pixel;
    wire [24:0] out_word_addr = target_base + image_offset + out_pixel;

    // Gather R, G and B from the core's byte stream, then issue one 24-bit
    // SDRAM write per pixel instead of three byte-masked writes. This cuts
    // output-side SDRAM transactions by 3x.
    wire [3:0] output_dqm = 4'b1000; // write DQ[23:0], mask unused DQ[31:24]
    wire [31:0] output_wdata = {8'h00, red_hold, green_hold, output_byte};

    assign mem_req_valid = (state == S_IN_REQ) || (state == S_OUT_REQ);
    assign mem_req_write = (state == S_OUT_REQ);
    assign mem_req_addr  = (state == S_OUT_REQ) ? out_word_addr : in_word_addr;
    assign mem_req_wdata = output_wdata;
    assign mem_req_dqm   = (state == S_OUT_REQ) ? output_dqm : 4'b1111;
    assign busy = (state != S_IDLE);
    assign debug_block = block_no;

    function [7:0] select_channel;
        input [31:0] word_value;
        input [1:0] channel;
        begin
            case (channel)
                2'd0: select_channel = word_value[23:16];
                2'd1: select_channel = word_value[15:8];
                default: select_channel = word_value[7:0];
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            decrypt_mode   <= 1'b0;
            image_no       <= 0;
            block_no       <= 0;
            byte_no        <= 0;
            in_pixel       <= 0;
            in_channel     <= 0;
            block_pixel    <= 0;
            block_channel  <= 0;
            out_pixel      <= 0;
            out_channel    <= 0;
            pixel_cache    <= 0;
            cache_pixel    <= 0;
            cache_valid    <= 1'b0;
            byte_hold      <= 0;
            output_byte    <= 0;
            red_hold       <= 0;
            green_hold     <= 0;
            cmd_start      <= 1'b0;
            cmd_decrypt    <= 1'b0;
            in_wr_en       <= 1'b0;
            in_wr_addr     <= 0;
            in_wr_data     <= 0;
            out_rd_addr    <= 0;
            encrypt_done   <= 1'b0;
            decrypt_done   <= 1'b0;
        end else begin
            cmd_start    <= 1'b0;
            in_wr_en     <= 1'b0;
            encrypt_done <= 1'b0;
            decrypt_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (core_ready && start_encrypt) begin
                        decrypt_mode <= 1'b0;
                        image_no <= 0;
                        block_no <= 0;
                        byte_no <= 0;
                        in_pixel <= 0;
                        in_channel <= 0;
                        cache_valid <= 1'b0;
                        state <= S_BLOCK;
                    end else if (core_ready && start_decrypt) begin
                        decrypt_mode <= 1'b1;
                        image_no <= 0;
                        block_no <= 0;
                        byte_no <= 0;
                        in_pixel <= 0;
                        in_channel <= 0;
                        cache_valid <= 1'b0;
                        state <= S_BLOCK;
                    end
                end

                S_BLOCK: begin
                    block_pixel   <= in_pixel;
                    block_channel <= in_channel;
                    byte_no       <= 0;
                    state         <= S_IN_PREP;
                end

                // Read one 32-bit pixel only when the stream enters a new
                // pixel. Bytes 1 and 2 reuse the cached RGB word.
                S_IN_PREP: begin
                    if (cache_valid && (cache_pixel == in_pixel) && (in_channel != 2'd0)) begin
                        byte_hold <= select_channel(pixel_cache, in_channel);
                        state <= S_IN_PUSH;
                    end else begin
                        state <= S_IN_REQ;
                    end
                end
                S_IN_REQ: begin
                    if (mem_req_ready) state <= S_IN_WAIT;
                end
                S_IN_WAIT: begin
                    if (mem_rsp_valid) begin
                        pixel_cache <= mem_rsp_data;
                        cache_pixel <= in_pixel;
                        cache_valid <= 1'b1;
                        byte_hold <= select_channel(mem_rsp_data, in_channel);
                        state <= S_IN_PUSH;
                    end
                end
                S_IN_PUSH: begin
                    in_wr_en   <= 1'b1;
                    in_wr_addr <= byte_no;
                    in_wr_data <= byte_hold;
                    if (in_channel == 2'd2) begin
                        in_channel <= 0;
                        in_pixel <= in_pixel + 1'b1;
                    end else begin
                        in_channel <= in_channel + 1'b1;
                    end
                    if (byte_no == 8'hff) begin
                        state <= S_CMD;
                    end else begin
                        byte_no <= byte_no + 1'b1;
                        state <= S_IN_PREP;
                    end
                end

                S_CMD: begin
                    cmd_decrypt <= decrypt_mode;
                    cmd_start <= 1'b1;
                    state <= S_CMD_GAP;
                end
                S_CMD_GAP: state <= S_WAIT_CLEAR;
                S_WAIT_CLEAR: if (!core_done) state <= S_WAIT_DONE;
                S_WAIT_DONE: if (core_done && !core_busy) begin
                    byte_no <= 0;
                    out_pixel <= block_pixel;
                    out_channel <= block_channel;
                    state <= S_OUT_ADDR;
                end

                S_OUT_ADDR: begin
                    out_rd_addr <= byte_no;
                    state <= S_OUT_LATCH;
                end
                S_OUT_LATCH: begin
                    // The core emits a continuous RGB byte stream. Blocks are
                    // 256 bytes, so a block can end in the middle of a pixel;
                    // preserve the partial R/G bytes across block boundaries.
                    if (out_channel == 2'd0) begin
                        red_hold <= out_rd_data;
                        out_channel <= 2'd1;
                        if (byte_no == 8'hff) state <= S_BLOCK_NEXT;
                        else begin
                            byte_no <= byte_no + 1'b1;
                            state <= S_OUT_ADDR;
                        end
                    end else if (out_channel == 2'd1) begin
                        green_hold <= out_rd_data;
                        out_channel <= 2'd2;
                        if (byte_no == 8'hff) state <= S_BLOCK_NEXT;
                        else begin
                            byte_no <= byte_no + 1'b1;
                            state <= S_OUT_ADDR;
                        end
                    end else begin
                        output_byte <= out_rd_data;
                        state <= S_OUT_REQ;
                    end
                end
                S_OUT_REQ: begin
                    if (mem_req_ready) state <= S_OUT_WAIT;
                end
                S_OUT_WAIT: begin
                    if (mem_rsp_valid) begin
                        out_channel <= 2'd0;
                        out_pixel <= out_pixel + 1'b1;
                        if (byte_no == 8'hff) begin
                            state <= S_BLOCK_NEXT;
                        end else begin
                            byte_no <= byte_no + 1'b1;
                            state <= S_OUT_ADDR;
                        end
                    end
                end

                S_BLOCK_NEXT: begin
                    if (block_no == BLOCKS_PER_IMAGE-1) begin
                        if (image_no == IMAGE_COUNT-1) begin
                            state <= S_IDLE;
                            if (decrypt_mode) decrypt_done <= 1'b1;
                            else encrypt_done <= 1'b1;
                        end else begin
                            image_no <= image_no + 1'b1;
                            block_no <= 0;
                            in_pixel <= 0;
                            in_channel <= 0;
                            cache_valid <= 1'b0;
                            state <= S_BLOCK;
                        end
                    end else begin
                        block_no <= block_no + 1'b1;
                        state <= S_BLOCK;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
