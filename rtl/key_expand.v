
module key_expand (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         ce,             // clock enable (slow section)
    input  wire         clear,          // NEW: re-initialise LFSR (pulse with key-gen start)
    input  wire         reseed,         
    input  wire [31:0]  chaotic_word,   
    output wire         key_bit_out,
    output wire         key_bit_valid
);

    reg [31:0] lfsr_state;
    reg        valid_reg;


    wire feedback = lfsr_state[31] ^ lfsr_state[21] ^ lfsr_state[1] ^ lfsr_state[0];

    always @(posedge clk) begin
        if (!rst_n) begin
            lfsr_state <= 32'hACE1ACE1; 
            valid_reg  <= 1'b0;
        end else if (!ce) begin
            // hold
        end else if (clear) begin
            lfsr_state <= 32'hACE1ACE1;   // deterministic restart: key no longer depends on idle cycles since reset
            valid_reg  <= 1'b0;
        end else if (reseed) begin
            lfsr_state <= lfsr_state ^ chaotic_word; 
            valid_reg  <= 1'b0;
        end else begin
            lfsr_state <= {lfsr_state[30:0], feedback}; 
            valid_reg  <= 1'b1;
        end
    end

    assign key_bit_out   = lfsr_state[0];
    assign key_bit_valid = valid_reg;

endmodule
