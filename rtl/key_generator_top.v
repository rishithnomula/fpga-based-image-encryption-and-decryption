
module key_generator_top (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                start,
    input  wire                ce,            // clock enable (slow section)
    input  wire signed [31:0]  seed_x1,
    input  wire signed [31:0]  seed_x2,
    input  wire signed [31:0]  seed_x3,
    input  wire signed [31:0]  seed_x4,
    input  wire signed [31:0]  seed_x5,
    input  wire signed [31:0]  seed_x6,
    input  wire signed [31:0]  seed_x7,
    input  wire signed [31:0]  seed_x8,

    output wire                mem_ready,      // high once all 256 bytes are filled

    input  wire [7:0]          data_rd_addr,   // read address (0-255)
    output reg  [7:0]          data_rd_data    // registered read data, 1-cycle latency
);

   

    // start request is latched until the next clock-enable tick, then consumed (one virtual cycle)
    reg start_p;
    always @(posedge clk) begin
        if (!rst_n) start_p <= 1'b0;
        else if (start) start_p <= 1'b1;
        else if (ce) start_p <= 1'b0;
    end

    wire signed [31:0] x1, x2, x3, x4, x5, x6, x7, x8;
    wire               chaotic_valid;
    reg                load_seed_pulse;

    chaotic8d_core u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .ce         (ce),
        .load_seed  (load_seed_pulse),
        .seed_x1    (seed_x1), .seed_x2(seed_x2), .seed_x3(seed_x3), .seed_x4(seed_x4),
        .seed_x5    (seed_x5), .seed_x6(seed_x6), .seed_x7(seed_x7), .seed_x8(seed_x8),
        .x1(x1), .x2(x2), .x3(x3), .x4(x4), .x5(x5), .x6(x6), .x7(x7), .x8(x8),
        .valid      (chaotic_valid)
    );

   
    reg        reseed_pulse;
    reg [2:0]  word_select;
    reg [31:0] selected_word;

    always @(posedge clk) begin
        if (!rst_n) begin
            load_seed_pulse <= 1'b0;
            reseed_pulse    <= 1'b0;
            word_select     <= 3'd0;
            selected_word   <= 32'd0;
        end else if (!ce) begin
            // hold
        end else if (start_p) begin
            load_seed_pulse <= 1'b1;
            reseed_pulse    <= 1'b0;
            word_select     <= 3'd0;
        end else begin
            load_seed_pulse <= 1'b0;

            if (chaotic_valid) begin
                reseed_pulse <= 1'b1;
                word_select  <= word_select + 3'd1;
                case (word_select)
                    3'd0: selected_word <= x1;
                    3'd1: selected_word <= x2;
                    3'd2: selected_word <= x3;
                    3'd3: selected_word <= x4;
                    3'd4: selected_word <= x5;
                    3'd5: selected_word <= x6;
                    3'd6: selected_word <= x7;
                    default: selected_word <= x8;
                endcase
            end else begin
                reseed_pulse <= 1'b0;
            end
        end
    end

  
    wire key_bit;
    wire key_bit_valid;

    key_expand u_expand (
        .clk           (clk),
        .rst_n         (rst_n),
        .ce            (ce),
        .clear         (start_p),
        .reseed        (reseed_pulse),
        .chaotic_word  (selected_word),
        .key_bit_out   (key_bit),
        .key_bit_valid (key_bit_valid)
    );

  
    reg [7:0] byte_acc;      // shift register building up one byte
    reg [2:0] bit_count;     // counts 0..7 bits collected so far
    reg [8:0] write_addr;    // counts 0..256 (9 bits needed to reach 256)
    reg       ready_reg;

    reg [7:0] mem [0:255];   // the 256x8 addressable key memory

    always @(posedge clk) begin
        if (!rst_n) begin
            byte_acc   <= 8'd0;
            bit_count  <= 3'd0;
            write_addr <= 9'd0;
            ready_reg  <= 1'b0;
        end else if (!ce) begin
            // hold
        end else if (start_p) begin
            // fresh generation run starting - clear packer state
            byte_acc   <= 8'd0;
            bit_count  <= 3'd0;
            write_addr <= 9'd0;
            ready_reg  <= 1'b0;
        end else if (!ready_reg && key_bit_valid) begin
            byte_acc  <= {byte_acc[6:0], key_bit};
            bit_count <= bit_count + 3'd1;

            if (bit_count == 3'd7) begin
                // 8th bit just arrived - the byte is complete
                mem[write_addr[7:0]] <= {byte_acc[6:0], key_bit};
                bit_count <= 3'd0;

                if (write_addr == 9'd255) begin
                    ready_reg <= 1'b1;   // all 256 addresses filled
                end else begin
                    write_addr <= write_addr + 9'd1;
                end
            end
        end
    end

    assign mem_ready = ready_reg;
    always @(posedge clk) begin
        data_rd_data <= mem[data_rd_addr];
    end

endmodule
