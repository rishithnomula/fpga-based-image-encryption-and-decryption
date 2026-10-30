// 24-bit-wide image memory: 1 write port, 1 registered read port (maps to M9K blocks).
// USE_INIT=1 pre-loads the contents from INIT_FILE (hex, one 24-bit RRGGBB word per line).
module ram24 #(
    parameter AW        = 14,
    parameter USE_INIT  = 0,
    parameter INIT_FILE = "images24.hex"
)(
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] wa,
    input  wire [23:0]   wd,
    input  wire [AW-1:0] ra,
    output reg  [23:0]   rd
);
    (* ramstyle = "M9K" *) reg [23:0] mem [0:(1<<AW)-1];
    generate if (USE_INIT) begin : g_init
        initial $readmemh(INIT_FILE, mem);
    end endgenerate
    // simulation only: start blank so unused areas display black instead of X
    // synthesis translate_off
    integer k;
    initial if (!USE_INIT) for (k = 0; k < (1<<AW); k = k + 1) mem[k] = 24'h000000;
    // synthesis translate_on
    always @(posedge clk) begin
        if (we) mem[wa] <= wd;
        rd <= mem[ra];
    end
endmodule
