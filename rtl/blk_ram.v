// 256 x 8 block buffer: one synchronous write port, one asynchronous read port.
module blk_ram (
    input  wire       clk,
    input  wire       we,
    input  wire [7:0] waddr,
    input  wire [7:0] wdata,
    input  wire [7:0] raddr,
    output wire [7:0] rdata
);
    reg [7:0] mem [0:255];
    always @(posedge clk) if (we) mem[waddr] <= wdata;
    assign rdata = mem[raddr];
endmodule
