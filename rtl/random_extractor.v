// =============================================================
// random_extractor.v
// -------------------------------------------------------------
// Turns the Rule 30 generator's single-bit-per-cycle output into
// a usable random number r in the range [0, modulus-1], for use
// as the random index in a Fisher-Yates shuffle.
//
// Usage pattern (driven by the shuffle engine, built next):
//   1. Set 'modulus' = i + 1 (current Fisher-Yates loop range)
//   2. Pulse 'start' for one cycle
//   3. This module raises 'ca_enable' for 8 cycles, shifting in
//      one bit per cycle from the Rule 30 generator's out_bit
//      (connect ca_bit to that generator's out_bit externally)
//   4. It computes random_val = raw_8bit_value % modulus
//   5. 'valid' pulses high for one cycle when random_val is ready
//
// NOTE ON BIAS: using modulus reduction on a fixed-width value
// introduces slight non-uniformity when modulus is not a power
// of 2. This is a standard, accepted simplification for
// hardware Fisher-Yates implementations at this scale.
// =============================================================

module random_extractor (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ce,         // clock enable (slow section: the % path gets CE_DIV clocks)
    input  wire        start,      // pulse: begin collecting a new random draw
    input  wire [8:0]  modulus,    // current range = i + 1 (2 .. 256)
    input  wire        ca_bit,     // one bit per cycle, from rule30_generator.out_bit
    output reg          ca_enable,  // drive rule30_generator.enable while collecting
    output reg  [7:0]  random_val, // result: raw_byte % modulus
    output reg          valid       // pulses high for 1 cycle when random_val is ready
);

    localparam IDLE    = 3'd0,
               PRIME   = 3'd1,
               COLLECT = 3'd2,
               COMPUTE = 3'd3,
               DONE    = 3'd4;

    reg [2:0] state;
    reg [2:0] bit_count;   // counts 0..7 across the 8 collection cycles
    reg [7:0] raw_byte;

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= IDLE;
            ca_enable  <= 1'b0;
            bit_count  <= 3'd0;
            raw_byte   <= 8'd0;
            random_val <= 8'd0;
            valid      <= 1'b0;
        end else if (ce) begin
            valid <= 1'b0; // default low; only pulses in DONE

            case (state)
                IDLE: begin
                    ca_enable <= 1'b0;
                    if (start) begin
                        bit_count <= 3'd0;
                        raw_byte  <= 8'd0;
                        ca_enable <= 1'b1;
                        state     <= PRIME;
                    end
                end

                PRIME: begin
                    ca_enable <= 1'b1;
                    state     <= COLLECT;
                end

                COLLECT: begin
                    ca_enable <= 1'b1;                       // step the CA this cycle
                    raw_byte  <= {raw_byte[6:0], ca_bit};    // shift in the new bit
                    if (bit_count == 3'd7)
                        state <= COMPUTE;
                    bit_count <= bit_count + 1'b1;
                end

                COMPUTE: begin
                    ca_enable  <= 1'b0;
                    random_val <= raw_byte % modulus;        // reduce into [0, modulus-1]
                    state      <= DONE;
                end

                DONE: begin
                    valid <= 1'b1;   // tells the shuffle engine the result is ready
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
