// =============================================================
// stage_process.v
// -------------------------------------------------------------
// Fused XOR + permutation engine for one encryption/decryption
// stage. Operates on a 256-byte block.
//
// ENCRYPT (decrypt_mode = 0), using the FORWARD table:
//     for k = 0..255:
//         out[k] = data[ FWD[k] ]  XOR  key[ FWD[k] ]
//     (both data and key are read at the permuted address)
//
// DECRYPT (decrypt_mode = 1), using the INVERSE table:
//     for j = 0..255:
//         out[j] = data[ INV[j] ]  XOR  key[j]
//     (data is read at the inverse-permuted address, but key is
//      read at the plain/original address -- this asymmetry is
//      correct: XOR was never spatially permuted in the first
//      place, only the data positions were)
//
// Wire 'table_rd_addr/table_rd_data' to whichever permutation
// table is relevant (forward table for encrypt, inverse table
// for decrypt). Wire 'data_rd_addr/data_rd_data' to the input
// block buffer (e.g. img2bits or the previous stage's output).
// Wire 'key_rd_addr/key_rd_data' to that stage's key memory.
// =============================================================

module stage_process (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire       decrypt_mode,   // 0 = encrypt, 1 = decrypt
    output reg          done,

    // permutation table read port (FWD for encrypt, INV for decrypt)
    output reg  [7:0] table_rd_addr,  // = out_idx
    input  wire [7:0] table_rd_data,  // = table[out_idx]

    // input data block read port
    output wire [7:0] data_rd_addr,   // = table_rd_data  (always the permuted address)
    input  wire [7:0] data_rd_data,

    // key block read port
    output wire [7:0] key_rd_addr,    // encrypt: = table_rd_data | decrypt: = out_idx
    input  wire [7:0] key_rd_data,

    // output block write port
    output reg          out_wr_en,
    output reg  [7:0] out_wr_addr,
    output reg  [7:0] out_wr_data
);

    localparam S_IDLE   = 3'd0,
               S_TBL     = 3'd1,   // present table_rd_addr = out_idx
               S_DERIVE  = 3'd2,   // table_rd_data now valid; data/key addrs derive from it
               S_READ    = 3'd3,   // data_rd_data / key_rd_data now valid; compute + write
               S_DONE    = 3'd4;

    reg [2:0] state;
    reg [7:0] out_idx;

    assign data_rd_addr = table_rd_data;
    assign key_rd_addr  = decrypt_mode ? out_idx : table_rd_data;

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            out_idx     <= 8'd0;
            table_rd_addr <= 8'd0;
            out_wr_en   <= 1'b0;
        end else begin
            out_wr_en <= 1'b0; // default; pulses only in S_READ

            case (state)
                S_IDLE: begin
                    if (start) begin
                        done    <= 1'b0;
                        out_idx <= 8'd0;
                        state   <= S_TBL;
                    end
                end

                S_TBL: begin
                    table_rd_addr <= out_idx;  // one full cycle for table_rd_data to settle
                    state         <= S_DERIVE;
                end

                S_DERIVE: begin
                    // table_rd_data is now valid; data_rd_addr/key_rd_addr derive from it
                    // combinationally. One more full cycle needed for the EXTERNAL data/key
                    // memories to reflect those addresses.
                    state <= S_READ;
                end

                S_READ: begin
                    out_wr_en   <= 1'b1;
                    out_wr_addr <= out_idx;
                    out_wr_data <= data_rd_data ^ key_rd_data;

                    if (out_idx == 8'd255) begin
                        state <= S_DONE;
                    end else begin
                        out_idx <= out_idx + 8'd1;
                        state   <= S_TBL;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    if (start) begin
                        done    <= 1'b0;
                        out_idx <= 8'd0;
                        state   <= S_TBL;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
