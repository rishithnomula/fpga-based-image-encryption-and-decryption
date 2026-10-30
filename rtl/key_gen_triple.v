
module key_gen_triple (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,          // pulse to start all three generators together
    input  wire         ce,             // clock enable (slow section)

    // Seed 1 (feeds Key1 -> Stage 1, Josephus)
    input  wire signed [31:0] seed1_x1, seed1_x2, seed1_x3, seed1_x4,
    input  wire signed [31:0] seed1_x5, seed1_x6, seed1_x7, seed1_x8,

    // Seed 2 (feeds Key2 -> Stage 2, Process Queue)
    input  wire signed [31:0] seed2_x1, seed2_x2, seed2_x3, seed2_x4,
    input  wire signed [31:0] seed2_x5, seed2_x6, seed2_x7, seed2_x8,

    // Seed 3 (feeds Key3 -> Stage 3, Rule 30)
    input  wire signed [31:0] seed3_x1, seed3_x2, seed3_x3, seed3_x4,
    input  wire signed [31:0] seed3_x5, seed3_x6, seed3_x7, seed3_x8,

    // Key 1 memory interface
    output wire         key1_mem_ready,
    input  wire [7:0]   key1_rd_addr,
    output wire [7:0]   key1_rd_data,

    // Key 2 memory interface
    output wire         key2_mem_ready,
    input  wire [7:0]   key2_rd_addr,
    output wire [7:0]   key2_rd_data,

    // Key 3 memory interface
    output wire         key3_mem_ready,
    input  wire [7:0]   key3_rd_addr,
    output wire [7:0]   key3_rd_data
);

    key_generator_top u_key1 (
        .clk(clk), .rst_n(rst_n), .start(start), .ce(ce),
        .seed_x1(seed1_x1), .seed_x2(seed1_x2), .seed_x3(seed1_x3), .seed_x4(seed1_x4),
        .seed_x5(seed1_x5), .seed_x6(seed1_x6), .seed_x7(seed1_x7), .seed_x8(seed1_x8),
        .mem_ready(key1_mem_ready),
        .data_rd_addr(key1_rd_addr),
        .data_rd_data(key1_rd_data)
    );

    key_generator_top u_key2 (
        .clk(clk), .rst_n(rst_n), .start(start), .ce(ce),
        .seed_x1(seed2_x1), .seed_x2(seed2_x2), .seed_x3(seed2_x3), .seed_x4(seed2_x4),
        .seed_x5(seed2_x5), .seed_x6(seed2_x6), .seed_x7(seed2_x7), .seed_x8(seed2_x8),
        .mem_ready(key2_mem_ready),
        .data_rd_addr(key2_rd_addr),
        .data_rd_data(key2_rd_data)
    );

    key_generator_top u_key3 (
        .clk(clk), .rst_n(rst_n), .start(start), .ce(ce),
        .seed_x1(seed3_x1), .seed_x2(seed3_x2), .seed_x3(seed3_x3), .seed_x4(seed3_x4),
        .seed_x5(seed3_x5), .seed_x6(seed3_x6), .seed_x7(seed3_x7), .seed_x8(seed3_x8),
        .mem_ready(key3_mem_ready),
        .data_rd_addr(key3_rd_addr),
        .data_rd_data(key3_rd_data)
    );

endmodule
