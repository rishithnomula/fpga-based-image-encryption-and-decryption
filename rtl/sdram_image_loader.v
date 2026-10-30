// -----------------------------------------------------------------------------
// Two-image boot loader backed by a Cyclone IV E M9K true dual-port RAM.
//
// Port A reads the bitstream initialisation image while pixels are written to
// external SDRAM. Port B writes each SDRAM readback pixel into the same M9K;
// after loading, Port B becomes the synchronous VGA scanout read port.
//
// The M9K physical depth is 32768 words (15 address bits). Only the first
// PIXELS=32256 words are valid image data; the MIF initialisation file is
// padded with zeros to the full physical depth.
// -----------------------------------------------------------------------------
module sdram_image_loader #(
    parameter INIT_FILE = "images2.mif",
    parameter PIXELS = 32256,
    parameter ADDR_WIDTH = 15
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  sdram_ready,
    output wire                  req_valid,
    input  wire                  req_ready,
    output wire                  req_write,
    output wire [24:0]           req_addr,
    output wire [31:0]           req_wdata,
    output wire [3:0]            req_dqm,
    input  wire                  rsp_valid,
    input  wire [31:0]           rsp_rdata,
    input  wire [ADDR_WIDTH-1:0] vga_addr,
    output wire [23:0]           vga_data,
    output reg                   done
);
    localparam integer MEM_DEPTH = (1 << ADDR_WIDTH);

    localparam [2:0]
        L_WAIT_READY = 3'd0,
        L_ROM_READ   = 3'd1,
        L_WRITE_REQ  = 3'd2,
        L_WRITE_WAIT = 3'd3,
        L_READ_REQ   = 3'd4,
        L_READ_WAIT  = 3'd5,
        L_DONE       = 3'd6;

    reg [ADDR_WIDTH-1:0] index;
    reg [2:0] state;

    wire [23:0] rom_q;
    wire image_writeback = (state == L_READ_WAIT) && rsp_valid;
    wire [ADDR_WIDTH-1:0] image_b_addr = image_writeback ? index : vga_addr;

    // Explicit primitive prevents Quartus from expanding the 32768x24 array
    // into flip-flops. Port A has a CLOCK0 output register for the boot read.
    // Port B registers its address on CLOCK1 and has an unregistered output,
    // giving one-cycle synchronous VGA read latency; it also writes readback.
    altsyncram #(
        .address_reg_b("CLOCK1"),
        .clock_enable_input_a("BYPASS"),
        .clock_enable_input_b("BYPASS"),
        .clock_enable_output_a("BYPASS"),
        .clock_enable_output_b("BYPASS"),
        .indata_reg_b("CLOCK1"),
        .intended_device_family("Cyclone IV E"),
        .lpm_type("altsyncram"),
        .numwords_a(MEM_DEPTH),
        .numwords_b(MEM_DEPTH),
        .operation_mode("BIDIR_DUAL_PORT"),
        .outdata_aclr_a("NONE"),
        .outdata_aclr_b("NONE"),
        .outdata_reg_a("CLOCK0"),
        .outdata_reg_b("UNREGISTERED"),
        .power_up_uninitialized("FALSE"),
        .ram_block_type("M9K"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .widthad_a(ADDR_WIDTH),
        .widthad_b(ADDR_WIDTH),
        .width_a(24),
        .width_b(24),
        .width_byteena_a(1),
        .width_byteena_b(1),
        .wrcontrol_wraddress_reg_b("CLOCK1"),
        .byteena_reg_b("CLOCK1"),
        .init_file(INIT_FILE)
    ) image_m9k (
        .address_a(index),
        .address_b(image_b_addr),
        .byteena_a(1'b1),
        .byteena_b(1'b1),
        .clock0(clk),
        .clock1(clk),
        .clocken0(1'b1),
        .clocken1(1'b1),
        .data_a(24'd0),
        .data_b(rsp_rdata[23:0]),
        .q_a(rom_q),
        .q_b(vga_data),
        .rden_a(1'b1),
        .rden_b(1'b1),
        .wren_a(1'b0),
        .wren_b(image_writeback)
    );

    assign req_valid = ((state == L_WRITE_REQ) || (state == L_READ_REQ)) && sdram_ready;
    assign req_write = (state == L_WRITE_REQ);
    assign req_addr  = {{(25-ADDR_WIDTH){1'b0}}, index};
    assign req_wdata = {8'h00, rom_q};
    assign req_dqm   = req_write ? 4'b0000 : 4'b1111;

    always @(posedge clk) begin
        if (!rst_n) begin
            index <= {ADDR_WIDTH{1'b0}};
            state <= L_WAIT_READY;
            done  <= 1'b0;
        end else begin
            case (state)
                L_WAIT_READY: begin
                    if (sdram_ready) state <= L_ROM_READ;
                end
                L_ROM_READ: begin
                    if (sdram_ready) state <= L_WRITE_REQ;
                end
                L_WRITE_REQ: begin
                    if (req_ready) state <= L_WRITE_WAIT;
                end
                L_WRITE_WAIT: begin
                    if (rsp_valid) state <= L_READ_REQ;
                end
                L_READ_REQ: begin
                    if (req_ready) state <= L_READ_WAIT;
                end
                L_READ_WAIT: begin
                    if (rsp_valid) begin
                        if (index == PIXELS-1) begin
                            done  <= 1'b1;
                            state <= L_DONE;
                        end else begin
                            index <= index + 1'b1;
                            state <= L_ROM_READ;
                        end
                    end
                end
                L_DONE: state <= L_DONE;
                default: state <= L_WAIT_READY;
            endcase
        end
    end

endmodule
