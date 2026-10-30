`timescale 1ns/1ps
// Self-checking system test for mie_core: init, encrypt, decrypt, determinism.
module mie_core_tb;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg  cmd_start = 0, cmd_decrypt = 0, in_wr_en = 0;
    reg  [7:0] in_wr_addr = 0, in_wr_data = 0, out_rd_addr = 0;
    wire ready, busy, done;
    wire [7:0] out_rd_data;

    mie_core dut (.clk(clk), .rst_n(rst_n), .ready(ready), .busy(busy), .done(done),
        .cmd_start(cmd_start), .cmd_decrypt(cmd_decrypt),
        .in_wr_en(in_wr_en), .in_wr_addr(in_wr_addr), .in_wr_data(in_wr_data),
        .out_rd_addr(out_rd_addr), .out_rd_data(out_rd_data));

    reg [7:0] plain [0:255];
    reg [7:0] cipher[0:255];
    reg [7:0] back  [0:255];
    integer i, errors, same, cyc;
    reg [31:0] lfsr;
    integer fd;

    // drive on falling edge => race free
    task load_block(input integer which);   // 0 = plain, 1 = cipher
        integer j;
        begin
            for (j = 0; j < 256; j = j + 1) begin
                @(negedge clk);
                in_wr_en = 1; in_wr_addr = j; in_wr_data = (which == 0) ? plain[j] : cipher[j];
            end
            @(negedge clk); in_wr_en = 0;
        end
    endtask
    task run_cmd(input dec);
        begin
            @(negedge clk); cmd_decrypt = dec; cmd_start = 1;
            @(negedge clk); cmd_start = 0;
            cyc = 0;
            while (!done && cyc < 200000) begin @(negedge clk); cyc = cyc + 1; end
            if (!done) begin $display("TIMEOUT waiting for done"); errors = errors + 1; end
            else $display("   command finished in %0d cycles", cyc);
        end
    endtask
    task read_block(input integer which);
        integer j;
        begin
            for (j = 0; j < 256; j = j + 1) begin
                out_rd_addr = j; #1;
                if (which == 1) cipher[j] = out_rd_data; else back[j] = out_rd_data;
            end
        end
    endtask

    initial begin
        errors = 0; lfsr = 32'hDEADBEEF;
        for (i = 0; i < 256; i = i + 1) begin
            lfsr = lfsr * 32'd1664525 + 32'd1013904223;
            plain[i] = (i < 128) ? lfsr[23:16] : (i % 16);    // half random, half structured
        end
        repeat (4) @(negedge clk); rst_n = 1;
        cyc = 0;
        while (!ready && cyc < 3000000) begin @(negedge clk); cyc = cyc + 1; end
        if (!ready) begin $display("FAIL: core never became ready"); $finish; end
        $display("[1] init finished after %0d cycles", cyc);

        load_block(0); run_cmd(0); read_block(1);
        same = 0; for (i = 0; i < 256; i = i + 1) if (cipher[i] == plain[i]) same = same + 1;
        $display("[2] encrypt done; %0d/256 bytes unchanged (chance level ~1)", same);
        if (same > 8) begin errors = errors + 1; $display("FAIL: ciphertext too similar"); end

        load_block(1); run_cmd(1); read_block(0);
        for (i = 0; i < 256; i = i + 1) if (back[i] !== plain[i]) begin
            errors = errors + 1; if (errors < 6) $display("MISMATCH %0d: %h vs %h", i, back[i], plain[i]);
        end
        $display("[3] decrypt done; round-trip %s", (errors == 0) ? "EXACT" : "BROKEN");

        // second block through the same hardware (different data, no re-init)
        for (i = 0; i < 256; i = i + 1) plain[i] = 8'hFF - i;
        load_block(0); run_cmd(0); read_block(1);
        load_block(1); run_cmd(1); read_block(0);
        for (i = 0; i < 256; i = i + 1) if (back[i] !== plain[i]) errors = errors + 1;
        $display("[4] second block round trip: %s", (errors == 0) ? "EXACT" : "BROKEN");

        // dump ciphertext of the 0xFF-i block for the cross-run determinism check
        fd = $fopen("mie_core_cipher.hex", "w");
        for (i = 0; i < 256; i = i + 1) $fdisplay(fd, "%02x", cipher[i]);
        $fclose(fd);

        if (errors == 0) $display("PASS: mie_core encrypt/decrypt verified.");
        else $display("FAIL: %0d error(s).", errors);
        $finish;
    end
endmodule
