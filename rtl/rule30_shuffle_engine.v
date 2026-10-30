// =============================================================
// rule30_shuffle_engine.v
// -------------------------------------------------------------
// Self-contained Rule 30 S-box generator. Instantiates
// rule30_generator and random_extractor internally, and runs
// the Fisher-Yates shuffle to build a 256-entry permutation
// table (indices 0..255).
//
// Usage:
//   1. Pulse 'start' for one cycle
//   2. 'done' goes high once the table is fully built
//   3. Read any entry via rd_addr -> rd_data (combinational read,
//      valid at any time, but only meaningful once done=1)
//
// Internal algorithm (Fisher-Yates):
//   mem[0..255] = identity (mem[k] = k)
//   for i = 255 downto 1:
//       r = random(0, i)          <- from random_extractor
//       swap(mem[i], mem[r])
//
// Indexing convention: this table is 0-indexed (values 0..255),
// NOT 1..256. Keep this consistent with the other two S-box
// modules (Josephus, Process Queue) at integration time.
// =============================================================

module rule30_shuffle_engine #(
    parameter CA_WIDTH = 4593   // width of the internal Rule 30 CA row (>= 2*2295+1 to stay boundary-free)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ce,         // clock enable (slow section)
    input  wire       start,      // pulse to begin building the table
    output reg         done,       // high once the table is ready; clears when start pulses
    input  wire [7:0] rd_addr,    // external read address (0..255)
    output wire [7:0] rd_data     // = mem[rd_addr]
);

    // -----------------------------------------------------------
    // Internal building blocks
    // -----------------------------------------------------------
    wire        ca_bit;
    wire        ca_enable;
    reg         rand_start;
    wire [8:0]  modulus;
    wire [7:0]  random_val;
    wire        rand_valid;

    rule30_generator #(.WIDTH(CA_WIDTH)) ca_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .ce        (ce),
        .enable    (ca_enable),
        .out_bit   (ca_bit),
        .state_out ()             // unused
    );

    random_extractor rand_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .ce         (ce),
        .start      (rand_start),
        .modulus    (modulus),
        .ca_bit     (ca_bit),
        .ca_enable  (ca_enable),
        .random_val (random_val),
        .valid      (rand_valid)
    );

    // -----------------------------------------------------------
    // The 256-entry permutation table itself
    // -----------------------------------------------------------
    reg [7:0] mem [0:255];
    assign rd_data = mem[rd_addr];

    // -----------------------------------------------------------
    // FSM
    // -----------------------------------------------------------
    localparam S_IDLE    = 3'd0,
               S_INIT     = 3'd1,   // load identity: mem[k] = k
               S_REQ_RAND = 3'd2,   // ask random_extractor for a draw
               S_WAIT_RAND= 3'd3,   // wait for rand_valid
               S_SWAP     = 3'd4,   // swap mem[shuffle_i] and mem[r]
               S_DONE     = 3'd5;

    reg [2:0] state;
    reg [7:0] init_idx;     // 0..255, used only during S_INIT
    reg [7:0] shuffle_i;    // 255 downto 1, the Fisher-Yates loop counter
    reg [7:0] r_captured;   // captured random_val for the current swap

    assign modulus = shuffle_i + 9'd1;  // range is [0, shuffle_i], size = shuffle_i+1

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            done       <= 1'b0;
            rand_start <= 1'b0;
            init_idx   <= 8'd0;
            shuffle_i  <= 8'd255;
            r_captured <= 8'd0;
        end else if (ce) begin
            rand_start <= 1'b0; // default; only pulsed explicitly below

            case (state)
                S_IDLE: begin
                    if (start) begin
                        done     <= 1'b0;
                        init_idx <= 8'd0;
                        state    <= S_INIT;
                    end
                end

                // Load mem[k] = k for k = 0..255
                S_INIT: begin
                    mem[init_idx] <= init_idx;
                    if (init_idx == 8'd255) begin
                        shuffle_i <= 8'd255;
                        state     <= S_REQ_RAND;
                    end else begin
                        init_idx <= init_idx + 8'd1;
                    end
                end

                // Ask for r = random(0, shuffle_i)
                S_REQ_RAND: begin
                    rand_start <= 1'b1;   // one-cycle pulse
                    state      <= S_WAIT_RAND;
                end

                S_WAIT_RAND: begin
                    if (rand_valid) begin
                        r_captured <= random_val;
                        state      <= S_SWAP;
                    end
                end

                // swap mem[shuffle_i] and mem[r_captured]
                S_SWAP: begin
                    mem[shuffle_i]  <= mem[r_captured];
                    mem[r_captured] <= mem[shuffle_i];

                    if (shuffle_i == 8'd1) begin
                        state <= S_DONE;
                    end else begin
                        shuffle_i <= shuffle_i - 8'd1;
                        state     <= S_REQ_RAND;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    if (start) begin
                        done     <= 1'b0;
                        init_idx <= 8'd0;
                        state    <= S_INIT;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
