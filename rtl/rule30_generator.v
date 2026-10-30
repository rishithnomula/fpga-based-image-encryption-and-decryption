// =============================================================
// rule30_generator.v
// -------------------------------------------------------------
// Generates a pseudorandom bit stream using Rule 30 Cellular
// Automata, matching the description in Section II-C of the
// reference paper (Megalli et al., SPSympo 2025):
//
//   s_i(t+1) = s_(i-1)(t) XOR ( s_i(t) OR s_(i+1)(t) )
//
// A row of WIDTH cells is seeded with a single '1' in the
// center cell (all others '0'), then stepped forward one row
// per clock cycle. The CENTER cell's value over time is the
// output pseudorandom bit stream (this is exactly what Fig. 3
// in the paper illustrates).
//
// Boundary cells (index 0 and WIDTH-1) have no left/right
// neighbor respectively -- treated as constant 0.
//
// WIDTH must be odd, and large enough that the boundary does
// not influence the center cell within the number of steps you
// plan to use: for N steps, WIDTH >= 2*N + 1.
// =============================================================

module rule30_generator #(
    parameter WIDTH = 4593             // number of CA cells; must be odd (>= 2*N+1 for N=2295 steps/frame)
)(
    input  wire             clk,
    input  wire             rst_n,     // active-low synchronous reset (re-seeds the row)
    input  wire             ce,        // clock enable (slow section)
    input  wire             enable,    // advance the CA by one step when high
    output wire             out_bit,   // pseudorandom bit, valid every cycle (from center cell)
    output wire [WIDTH-1:0] state_out  // full row, exposed for debug / waveform inspection
);

    localparam CENTER = WIDTH/2;       // integer division; center index for odd WIDTH

    reg [WIDTH-1:0] state;
    reg [WIDTH-1:0] next_state;

    // ---------------------------------------------------------
    // Combinational: compute the next CA row from the current one.
    // Vectorized form of  next[i] = state[i-1] ^ (state[i] | state[i+1])
    // with out-of-range neighbours treated as 0 (same behaviour as the
    // old per-bit loop, but ~100x faster in simulation).
    //   left  neighbour of cell i = state[i-1]  -> state shifted up
    //   right neighbour of cell i = state[i+1]  -> state shifted down
    // ---------------------------------------------------------
    wire [WIDTH-1:0] left_n  = {state[WIDTH-2:0], 1'b0};
    wire [WIDTH-1:0] right_n = {1'b0, state[WIDTH-1:1]};
    always @(*) next_state = left_n ^ (state | right_n);

    // ---------------------------------------------------------
    // Sequential: seed the row on reset, step forward on enable
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            // single '1' in the center, '0' everywhere else
            state <= {{CENTER{1'b0}}, 1'b1, {CENTER{1'b0}}};
        end else if (ce && enable) begin
            state <= next_state;
        end
    end

    assign out_bit   = state[CENTER];
    assign state_out = state;

endmodule
