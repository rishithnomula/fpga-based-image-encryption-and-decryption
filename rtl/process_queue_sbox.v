`timescale 1ns/1ps

module process_queue_sbox (
    input wire clk,
    input wire reset,
    input wire start,
    input wire ce,                // clock enable (slow section: the x^3 mod 257 path gets CE_DIV clocks)
    input wire [1023:0] prng_bits,

    // S-box read port (replaces the unpacked-array output port,
    // which is a SystemVerilog-only construct)
    input  wire [7:0] sbox_rd_addr,
    output wire [8:0] sbox_rd_data,

    output reg done,
    output reg busy
);

    localparam IDLE  = 3'd0;
    localparam INIT  = 3'd1;
    localparam FETCH = 3'd2;
    localparam CALC  = 3'd3;
    localparam WRITE = 3'd4;
    localparam DONE  = 3'd5;

    reg [2:0] state;

    reg [8:0] queue [0:255];
    reg [8:0] sbox  [0:255];   // internal-only now -> legal in plain Verilog

    reg [8:0] head;
    reg [8:0] tail;
    reg [8:0] count;

    reg [8:0] sbox_index;
    reg [10:0] bit_index;

    reg [8:0] current;
    reg [8:0] result;

    integer i;
    integer value;

    // start request is latched until the next clock-enable tick, then consumed (one virtual cycle)
    reg start_p;
    always @(posedge clk) begin
        if (reset) start_p <= 1'b0;
        else if (start) start_p <= 1'b1;
        else if (ce) start_p <= 1'b0;
    end

    // Combinational read port
    assign sbox_rd_data = sbox[sbox_rd_addr];

    always @(posedge clk) begin

        if (reset) begin

            state <= IDLE;
            done <= 1'b0;
            busy <= 1'b0;

            head <= 0;
            tail <= 0;
            count <= 0;

            sbox_index <= 0;
            bit_index <= 0;

            current <= 0;
            result <= 0;

        end

        else if (ce) begin

            case (state)

                IDLE: begin

                    busy <= 1'b0;

                    if (start_p) begin
                        busy <= 1'b1;
                        done <= 1'b0;
                        state <= INIT;
                    end

                end


                INIT: begin

                    for (i = 0; i < 256; i = i + 1) begin
                        queue[i] <= i + 1;
                        sbox[i] <= 0;
                    end

                    head <= 0;
                    tail <= 0;
                    count <= 256;

                    sbox_index <= 0;
                    bit_index <= 0;

                    state <= FETCH;

                end


                FETCH: begin

                    if (count == 0) begin
                        state <= DONE;
                    end

                    // bit_index[9:0] wraps the 11-bit counter back into the
                    // 1024-bit prng_bits window instead of reading past it.
                    else if (prng_bits[bit_index[9:0]] == 1'b0) begin

                        queue[tail] <= queue[head];

                        if (head == 255)
                            head <= 0;
                        else
                            head <= head + 1;

                        if (tail == 255)
                            tail <= 0;
                        else
                            tail <= tail + 1;

                        bit_index <= bit_index + 1;

                    end

                    else begin

                        current <= queue[head];

                        if (head == 255)
                            head <= 0;
                        else
                            head <= head + 1;

                        count <= count - 1;

                        bit_index <= bit_index + 1;

                        state <= CALC;

                    end

                end


                CALC: begin

                    value = current;

                    result <= (value * value * value) % 257;

                    state <= WRITE;

                end


                WRITE: begin

                    sbox[sbox_index] <= result;

                    if (count == 0) begin
                        state <= DONE;
                    end
                    else begin
                        sbox_index <= sbox_index + 1;
                        state <= FETCH;
                    end

                end


                DONE: begin

                    busy <= 1'b0;
                    done <= 1'b1;

                    state <= IDLE;

                end


                default: begin
                    state <= IDLE;
                    busy <= 1'b0;
                end

            endcase

        end

    end

endmodule
