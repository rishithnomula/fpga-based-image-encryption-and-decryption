`timescale 1ns/1ps

module josephus_seq_gen #(
    parameter MAX_M = 256,
    parameter IDX_W = 9
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire [IDX_W-1:0] m,
    input  wire [IDX_W-1:0] k,
    input  wire [IDX_W-1:0] x,

    output reg              seq_valid,
    output reg  [IDX_W-1:0] seq_val,
    output reg  [IDX_W-1:0] seq_idx,
    output reg              busy,
    output reg              done
);

    localparam IDLE = 2'b00;
    localparam INIT = 2'b01;
    localparam RUN  = 2'b10;
    localparam DONE = 2'b11;

    reg [1:0] state;

    reg [MAX_M-1:0] alive_bitmap;

    reg [IDX_W-1:0] ptr;
    reg [IDX_W-1:0] hop_cnt;
    reg [IDX_W-1:0] alive_cnt;
    reg [IDX_W-1:0] emit_cnt;   // index of the NEXT value to emit (0-based)

    integer i;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state        <= IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            seq_valid    <= 1'b0;
            seq_val      <= 0;
            seq_idx      <= 0;

            alive_bitmap <= 0;
            ptr          <= 0;
            hop_cnt      <= 0;
            alive_cnt    <= 0;
            emit_cnt     <= 0;

        end

        else begin

            seq_valid <= 1'b0;

            case (state)

              IDLE: begin

    busy <= 1'b0;

    if (start) begin

        busy  <= 1'b1;
        done  <= 1'b0;
        state <= INIT;

    end

                end


                INIT: begin

                    for (i = 0; i < MAX_M; i = i + 1) begin

                        if (i < m)
                            alive_bitmap[i] <= 1'b1;
                        else
                            alive_bitmap[i] <= 1'b0;

                    end

                    if (k == 0)
                        ptr <= 0;
                    else if (k > m)
                        ptr <= 0;
                    else
                        ptr <= k - 1'b1;

                    hop_cnt   <= 1;
                    alive_cnt <= m;
                    seq_idx   <= 0;
                    emit_cnt  <= 0;
                    seq_val   <= 0;

                    state <= RUN;

                end


                RUN: begin

                    if (alive_cnt == 0) begin

                        state <= DONE;

                    end

                    else if (alive_bitmap[ptr]) begin

                        if (hop_cnt == x) begin

                            alive_bitmap[ptr] <= 1'b0;

                            seq_val   <= ptr + 1'b1;
                            seq_valid <= 1'b1;

                            // seq_idx accompanies seq_valid in the SAME cycle (0-based)
                            seq_idx  <= emit_cnt;
                            emit_cnt <= emit_cnt + 1'b1;

                            hop_cnt   <= 1;
                            alive_cnt <= alive_cnt - 1'b1;

                            if (alive_cnt == 1) begin
                                state <= DONE;
                            end

                            if (ptr == m - 1'b1)
                                ptr <= 0;
                            else
                                ptr <= ptr + 1'b1;

                        end

                        else begin

                            hop_cnt <= hop_cnt + 1'b1;

                            if (ptr == m - 1'b1)
                                ptr <= 0;
                            else
                                ptr <= ptr + 1'b1;

                        end

                    end

                    else begin

                        if (ptr == m - 1'b1)
                            ptr <= 0;
                        else
                            ptr <= ptr + 1'b1;

                    end

                end


                DONE: begin

                    busy      <= 1'b0;
                    done      <= 1'b1;
                    seq_valid <= 1'b0;

                    state <= IDLE;

                end


                default: begin

                    state <= IDLE;
                    busy  <= 1'b0;
                    done  <= 1'b0;

                end

            endcase

        end

    end

endmodule