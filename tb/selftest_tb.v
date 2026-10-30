`timescale 1ns/1ps
// Checks the built-in self-test: normal run must PASS; with a deliberately corrupted S-box entry it must FAIL.
module selftest_tb;
    parameter CORRUPT = 0;
    reg clk = 0, rst_n = 0; always #10 clk = ~clk;
    wire ready, busy, done, sd, sp;
    mie_core dut (.clk(clk), .rst_n(rst_n), .ready(ready), .busy(busy), .done(done), .selftest_done(sd), .selftest_pass(sp),
        .cmd_start(1'b0), .cmd_decrypt(1'b0), .in_wr_en(1'b0), .in_wr_addr(8'd0), .in_wr_data(8'd0), .out_rd_addr(8'd0), .out_rd_data());
    integer cyc; reg done_corrupt = 0;
    initial begin
        #100 rst_n = 1; cyc = 0;
        while (!sd && cyc < 3000000) begin
            @(posedge clk); cyc = cyc + 1;
            if (CORRUPT && !done_corrupt && dut.st == 5'd18) begin dut.u_keys.u_key1.mem[0] = dut.u_keys.u_key1.mem[0] ^ 8'h01; done_corrupt = 1; end   // flip one key bit once, just before the self-test
        end
        $display("selftest_done=%b pass=%b ready=%b after %0d cycles (corrupt=%0d)", sd, sp, ready, cyc, CORRUPT);
        if (!CORRUPT && sd && sp && ready) $display("RESULT PASS: hardware self-test passes");
        else if (CORRUPT && sd && !sp) $display("RESULT PASS: self-test detects the corrupted table");
        else $display("RESULT FAIL");
        $finish;
    end
endmodule
