// =============================================================
// simple_pass.v  -- generic 256-byte pass engine (Member 3 glue)
//   KIND 0  XOR    : dst[i] = src[i] ^ aux[i]          (aux = key memory, 1-cycle read latency)
//   KIND 1  SUB    : dst[i] = aux[ src[i] ]            (aux = 256-entry substitution LUT, async)
//   KIND 2  GATHER : dst[i] = src[ aux[i] ]            (aux = 256-entry index table, async)
// Sequence per byte:  ADDR -> WAIT -> (write registered) -> NEXT
// =============================================================
module simple_pass (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] kind,
    input  wire       start,
    output reg        done,
    output wire [7:0] src_rd_addr,
    input  wire [7:0] src_rd_data,
    output wire [7:0] aux_rd_addr,
    input  wire [7:0] aux_rd_data,
    output reg        wr_en,
    output reg  [7:0] wr_addr,
    output reg  [7:0] wr_data
);
    localparam S_IDLE = 2'd0, S_ADDR = 2'd1, S_WAIT = 2'd2, S_NEXT = 2'd3;
    reg [1:0] st;
    reg [7:0] i;

    assign src_rd_addr = (kind == 2'd2) ? aux_rd_data : i;
    assign aux_rd_addr = (kind == 2'd1) ? src_rd_data : i;

    wire [7:0] result = (kind == 2'd0) ? (src_rd_data ^ aux_rd_data) :
                        (kind == 2'd1) ?  aux_rd_data : src_rd_data;

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IDLE; done <= 1'b0; wr_en <= 1'b0; i <= 8'd0;
            wr_addr <= 8'd0; wr_data <= 8'd0;
        end else begin
            wr_en <= 1'b0;
            case (st)
                S_IDLE: if (start) begin done <= 1'b0; i <= 8'd0; st <= S_ADDR; end
                S_ADDR: st <= S_WAIT;
                S_WAIT: begin
                    wr_en <= 1'b1; wr_addr <= i; wr_data <= result;
                    st <= S_NEXT;
                end
                S_NEXT: begin
                    if (i == 8'd255) begin done <= 1'b1; st <= S_IDLE; end
                    else begin i <= i + 8'd1; st <= S_ADDR; end
                end
            endcase
        end
    end
endmodule
