// SDRAM-to-on-chip display-cache DMA. Cipher/decrypted data stays in SDRAM;
// the synchronous M9K cache provides continuous VGA scanout.
module sdram_cache_dma #(
    parameter PIXELS = 32256,
    parameter ADDR_WIDTH = 15
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    input  wire [24:0]           source_base,
    output wire                  busy,
    output reg                   done,

    output wire                  mem_req_valid,
    input  wire                  mem_req_ready,
    output wire                  mem_req_write,
    output wire [24:0]           mem_req_addr,
    output wire [31:0]           mem_req_wdata,
    output wire [3:0]            mem_req_dqm,
    input  wire                  mem_rsp_valid,
    input  wire [31:0]           mem_rsp_data,

    output reg                   cache_we,
    output reg  [ADDR_WIDTH-1:0] cache_addr,
    output reg  [23:0]           cache_data
);
    reg [ADDR_WIDTH-1:0] index;
    reg [1:0] state;
    localparam S_IDLE=2'd0, S_REQ=2'd1, S_WAIT=2'd2;

    assign busy = (state != S_IDLE);
    assign mem_req_valid = (state == S_REQ);
    assign mem_req_write = 1'b0;
    assign mem_req_addr = source_base + index;
    assign mem_req_wdata = 32'd0;
    assign mem_req_dqm = 4'b1111;

    always @(posedge clk) begin
        if (!rst_n) begin
            index <= {ADDR_WIDTH{1'b0}};
            state <= S_IDLE;
            done <= 1'b0;
            cache_we <= 1'b0;
            cache_addr <= {ADDR_WIDTH{1'b0}};
            cache_data <= 24'd0;
        end else begin
            done <= 1'b0;
            cache_we <= 1'b0;
            case (state)
                S_IDLE: if (start) begin index <= 0; state <= S_REQ; end
                S_REQ: if (mem_req_ready) state <= S_WAIT;
                S_WAIT: if (mem_rsp_valid) begin
                    cache_we <= 1'b1;
                    cache_addr <= index;
                    cache_data <= mem_rsp_data[23:0];
                    if (index == PIXELS-1) begin
                        state <= S_IDLE;
                        done <= 1'b1;
                    end else begin
                        index <= index + 1'b1;
                        state <= S_REQ;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
