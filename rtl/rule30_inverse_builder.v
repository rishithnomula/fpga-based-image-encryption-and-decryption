// =============================================================
// rule30_inverse_builder.v
// -------------------------------------------------------------
// Given a completed forward permutation table (e.g. from
// rule30_shuffle_engine), builds its inverse:
//     INV[ FWD[k] ] = k   for k = 0..255
//
// Reads the forward table via a simple address/data port (wire
// this to rule30_shuffle_engine's rd_addr/rd_data once its
// 'done' is high), and exposes its own address/data read port
// for the inverse table once complete.
// =============================================================

module rule30_inverse_builder (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ce,           // clock enable (slow section)
    input  wire       start,        // pulse to begin (assumes forward table is already built)
    output reg         done,

    output reg  [7:0] fwd_rd_addr,  // drive this into the forward table's read address
    input  wire [7:0] fwd_rd_data,  // forward table's data out, one cycle after addr changes

    input  wire [7:0] inv_rd_addr,  // external read address for the inverse table
    output wire [7:0] inv_rd_data   // = inv_mem[inv_rd_addr]
);

    localparam S_IDLE    = 2'd0,
               S_SETADDR = 2'd1,   // present fwd_rd_addr = k
               S_WRITE   = 2'd2,   // fwd_rd_data now valid; write inv_mem[fwd_rd_data] = k
               S_DONE    = 2'd3;

    reg [1:0] state;
    reg [7:0] k;
    reg [7:0] inv_mem [0:255];

    assign inv_rd_data = inv_mem[inv_rd_addr];

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            k           <= 8'd0;
            fwd_rd_addr <= 8'd0;
        end else if (ce) begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        done  <= 1'b0;
                        k     <= 8'd0;
                        state <= S_SETADDR;
                    end
                end

                S_SETADDR: begin
                    fwd_rd_addr <= k;      // one full cycle to let fwd_rd_data settle
                    state       <= S_WRITE;
                end

                S_WRITE: begin
                    inv_mem[fwd_rd_data] <= k;
                    if (k == 8'd255) begin
                        state <= S_DONE;
                    end else begin
                        k     <= k + 8'd1;
                        state <= S_SETADDR;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
