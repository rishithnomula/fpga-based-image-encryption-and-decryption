`timescale 1ns / 1ps

module josephus_permute (
    clk,
    rst_n,
    seq_wr_en,
    seq_wr_addr,
    seq_wr_data,
    start,
    m,
    din_addr,
    din_data,
    dout_wr_en,
    dout_addr,
    dout_data,
    busy,
    done
);

    parameter MAX_M  = 256;
    parameter IDX_W  = 9;
    parameter DATA_W = 8;

    input  wire              clk;
    input  wire              rst_n;
    input  wire              seq_wr_en;
    input  wire  [IDX_W-1:0] seq_wr_addr;
    input  wire  [IDX_W-1:0] seq_wr_data;
    input  wire              start;
    input  wire  [IDX_W-1:0] m;

    output reg   [IDX_W-1:0] din_addr;
    input  wire  [DATA_W-1:0] din_data;

    output reg               dout_wr_en;
    output reg   [IDX_W-1:0] dout_addr;
    output reg   [DATA_W-1:0] dout_data;

    output reg               busy;
    output reg               done;

    reg [IDX_W-1:0] seq_ram [0:MAX_M-1];

    always @(posedge clk) begin
        if (seq_wr_en) begin
            seq_ram[seq_wr_addr] <= seq_wr_data;
        end
    end

    reg [IDX_W-1:0] idx;
    reg [1:0]       state;

    localparam IDLE  = 2'b00;
    localparam FETCH = 2'b01;
    localparam WRITE = 2'b10;
    localparam FIN   = 2'b11;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;
            dout_wr_en <= 1'b0;
            idx        <= {IDX_W{1'b0}};
            din_addr   <= {IDX_W{1'b0}};
            dout_addr  <= {IDX_W{1'b0}};
            dout_data  <= {DATA_W{1'b0}};
        end else begin
            case (state)
                IDLE: begin
                    done       <= 1'b0;
                    dout_wr_en <= 1'b0;
                    if (start) begin
                        state <= FETCH;
                        busy  <= 1'b1;
                        idx   <= {IDX_W{1'b0}};
                    end
                end

                FETCH: begin
                    dout_wr_en <= 1'b0;
                    if (idx < m) begin
                        din_addr  <= seq_ram[idx] - 1'b1;
                        dout_addr <= idx;
                        state     <= WRITE;
                    end else begin
                        state     <= FIN;
                    end
                end

               WRITE: begin
                    dout_data  <= din_data;
                    dout_wr_en <= 1'b1;  // <-- Fixed typo here
                    idx        <= idx + 1'b1;
                    state      <= FETCH;
                end

                FIN: begin
                    dout_wr_en <= 1'b0;
                    busy       <= 1'b0;
                    done       <= 1'b1;
                    state      <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule