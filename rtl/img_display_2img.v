// -----------------------------------------------------------------------------
// 640x480@60-style VGA scanout for two 112x144 RGB images.
//
// phase 0: Original image 1 | Original image 2. Each photo is 280x360.
// phase 1: Two rows, each with Original | Encrypted. Each photo is 186x240.
// phase 2: Two rows, each with Original | Encrypted | Decrypted.
//          Each photo is 186x240.
//
// Nearest-neighbour scaling uses Q16 reciprocal multiplication instead of
// run-time division. Pixel address is linear: image0[0..16127], image1[16128..32255].
// -----------------------------------------------------------------------------
module img_display_2img (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  phase,
    output reg  [14:0] rd_addr,
    input  wire [23:0] rd_plain,
    input  wire [23:0] rd_cipher,
    input  wire [23:0] rd_dec,
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_CLK,
    output wire        VGA_BLANK_N,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_SYNC_N
);
    localparam [23:0] BG = 24'h101018;
    localparam [14:0] IMAGE1_BASE = 15'd0;
    localparam [14:0] IMAGE2_BASE = 15'd16128;

    reg ph;
    reg [9:0] hc, vc;

    always @(posedge clk) begin
        if (!rst_n) begin
            ph <= 1'b0;
            hc <= 10'd0;
            vc <= 10'd0;
        end else begin
            ph <= ~ph;
            if (ph) begin
                if (hc == 10'd799) begin
                    hc <= 10'd0;
                    vc <= (vc == 10'd524) ? 10'd0 : vc + 10'd1;
                end else begin
                    hc <= hc + 10'd1;
                end
            end
        end
    end

    wire act = (hc < 10'd640) && (vc < 10'd480);
    wire hs_now = ~((hc >= 10'd656) && (hc < 10'd752));
    wire vs_now = ~((vc >= 10'd490) && (vc < 10'd492));

    reg panel_valid;
    reg image_sel;
    reg [1:0] panel_sel;
    reg [9:0] rel_x, rel_y;
    reg [9:0] panel_x0, panel_y0;

    always @* begin
        panel_valid = 1'b0;
        image_sel = 1'b0;
        panel_sel = 2'd0;
        rel_x = 10'd0;
        rel_y = 10'd0;
        panel_x0 = 10'd0;
        panel_y0 = 10'd0;

        if (phase == 2'd0) begin
            // 280x360 photo at x=20 / 340, y=60. Exact 2.5x enlargement.
            if ((vc >= 10'd60) && (vc < 10'd420)) begin
                if ((hc >= 10'd20) && (hc < 10'd300)) begin
                    panel_valid = 1'b1;
                    image_sel = 1'b0;
                    panel_x0 = 10'd20;
                    panel_y0 = 10'd60;
                end else if ((hc >= 10'd340) && (hc < 10'd620)) begin
                    panel_valid = 1'b1;
                    image_sel = 1'b1;
                    panel_x0 = 10'd340;
                    panel_y0 = 10'd60;
                end
            end
        end else if (phase == 2'd1) begin
            // Original/cipher columns; image 1 on top and image 2 below.
            if (vc < 10'd240) begin
                image_sel = 1'b0;
                panel_y0 = 10'd0;
            end else if (vc < 10'd480) begin
                image_sel = 1'b1;
                panel_y0 = 10'd240;
            end
            if (vc < 10'd480) begin
                if ((hc >= 10'd67) && (hc < 10'd253)) begin
                    panel_valid = 1'b1;
                    panel_sel = 2'd0;
                    panel_x0 = 10'd67;
                end else if ((hc >= 10'd387) && (hc < 10'd573)) begin
                    panel_valid = 1'b1;
                    panel_sel = 2'd1;
                    panel_x0 = 10'd387;
                end
            end
        end else begin
            // Original/cipher/decrypted columns; one image per row.
            if (vc < 10'd240) begin
                image_sel = 1'b0;
                panel_y0 = 10'd0;
            end else if (vc < 10'd480) begin
                image_sel = 1'b1;
                panel_y0 = 10'd240;
            end
            if (vc < 10'd480) begin
                if ((hc >= 10'd13) && (hc < 10'd199)) begin
                    panel_valid = 1'b1;
                    panel_sel = 2'd0;
                    panel_x0 = 10'd13;
                end else if ((hc >= 10'd226) && (hc < 10'd412)) begin
                    panel_valid = 1'b1;
                    panel_sel = 2'd1;
                    panel_x0 = 10'd226;
                end else if ((hc >= 10'd439) && (hc < 10'd625)) begin
                    panel_valid = 1'b1;
                    panel_sel = 2'd2;
                    panel_x0 = 10'd439;
                end
            end
        end

        if (panel_valid) begin
            rel_x = hc - panel_x0;
            rel_y = vc - panel_y0;
        end
    end

    // Q16 nearest-neighbour ratios:
    // phase 0: 112/280 = 144/360 = 0.4
    // phase 1/2: 112/186 ~= 0.60215, 144/240 = 0.6
    wire [15:0] scale_x_q16 = (phase == 2'd0) ? 16'd26214 : 16'd39474;
    wire [15:0] scale_y_q16 = (phase == 2'd0) ? 16'd26214 : 16'd39322;
    wire [25:0] src_x_product = {16'd0, rel_x} * scale_x_q16;
    wire [25:0] src_y_product = {16'd0, rel_y} * scale_y_q16;
    wire [6:0] src_x = src_x_product[22:16];
    wire [7:0] src_y = src_y_product[23:16];

    // y*112 = y*64 + y*32 + y*16; no general multiplier/divider is needed.
    wire [13:0] row64 = ({6'd0, src_y} << 6);
    wire [13:0] row32 = ({6'd0, src_y} << 5);
    wire [13:0] row16 = ({6'd0, src_y} << 4);
    wire [14:0] image_base = image_sel ? IMAGE2_BASE : IMAGE1_BASE;
    wire [14:0] pixel_addr = image_base + row64 + row32 + row16 + src_x;

    // Three-cycle metadata alignment: registered cache address, synchronous
    // cache read, pixel selection, then VGA output register.
    reg [1:0] panel_meta0, panel_meta1;
    reg valid_meta0, valid_meta1;
    reg active_meta0, active_meta1, active_meta2;
    reg hs_meta0, hs_meta1, hs_meta2;
    reg vs_meta0, vs_meta1, vs_meta2;
    reg [23:0] pixel_meta;
    reg [23:0] rgb_out;
    reg blank_out, hs_out, vs_out;

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_addr <= 15'd0;
            panel_meta0 <= 0; panel_meta1 <= 0;
            valid_meta0 <= 0; valid_meta1 <= 0;
            active_meta0 <= 0; active_meta1 <= 0; active_meta2 <= 0;
            hs_meta0 <= 1'b1; hs_meta1 <= 1'b1; hs_meta2 <= 1'b1;
            vs_meta0 <= 1'b1; vs_meta1 <= 1'b1; vs_meta2 <= 1'b1;
            pixel_meta <= BG;
            rgb_out <= 24'd0;
            blank_out <= 1'b0;
            hs_out <= 1'b1;
            vs_out <= 1'b1;
        end else begin
            rd_addr <= panel_valid ? pixel_addr : 15'd0;

            panel_meta0 <= panel_sel;
            panel_meta1 <= panel_meta0;
            valid_meta0 <= panel_valid;
            valid_meta1 <= valid_meta0;
            active_meta0 <= act;
            active_meta1 <= active_meta0;
            active_meta2 <= active_meta1;
            hs_meta0 <= hs_now;
            hs_meta1 <= hs_meta0;
            hs_meta2 <= hs_meta1;
            vs_meta0 <= vs_now;
            vs_meta1 <= vs_meta0;
            vs_meta2 <= vs_meta1;

            pixel_meta <= !valid_meta1 ? BG :
                          (panel_meta1 == 2'd0) ? rd_plain :
                          (panel_meta1 == 2'd1) ? rd_cipher : rd_dec;

            if (ph) begin
                rgb_out <= active_meta2 ? pixel_meta : 24'h000000;
                blank_out <= active_meta2;
                hs_out <= hs_meta2;
                vs_out <= vs_meta2;
            end
        end
    end

    assign VGA_R = rgb_out[23:16];
    assign VGA_G = rgb_out[15:8];
    assign VGA_B = rgb_out[7:0];
    assign VGA_CLK = ph;
    assign VGA_BLANK_N = blank_out;
    assign VGA_HS = hs_out;
    assign VGA_VS = vs_out;
    assign VGA_SYNC_N = 1'b0;
endmodule
