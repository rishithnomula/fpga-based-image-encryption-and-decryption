// =============================================================
// mie_core.v  --  Multi-Image Encryption core (Member 3: top-level integration)
// -------------------------------------------------------------
// One 256-byte block at a time, three stages (paper Fig. 1):
//
//   ENCRYPT  A --XOR K1--> B --Josephus perm--> A --XOR K2--> B
//              --Process-Queue S-box--> A --Rule30 (XOR K3 + perm)--> B
//   DECRYPT  A --Rule30^-1 (perm^-1 + XOR K3)--> B --S-box^-1--> A
//              --XOR K2--> B --Josephus perm^-1--> A --XOR K1--> B
//
// Host interface
//   * after reset the core initialises itself (keys, S-boxes, inverse tables);
//     `ready` goes high when that is finished.  Initialisation is fully
//     deterministic: same RTL + same parameters => same keys/S-boxes forever,
//     so data encrypted today can be decrypted after any later power cycle.
//   * write 256 plaintext/ciphertext bytes with in_wr_*  (only while ready & !busy)
//   * pulse cmd_start (cmd_decrypt selects direction)
//   * wait for done (level, cleared by the next cmd_start), then read the 256
//     result bytes through out_rd_addr/out_rd_data (async read).
// =============================================================
module mie_core #(
    parameter CA_WIDTH = 4593,           // Rule 30 CA row width (see rule30_shuffle_engine)
    parameter [8:0] JOS_M = 9'd256,      // Josephus: list size (must be 256)
    parameter [8:0] JOS_K = 9'd1,        // Josephus: start position
    parameter [8:0] JOS_X = 9'd7,        // Josephus: elimination step
    parameter CE_DIV   = 16              // slow-section clock enable: 1 active cycle in CE_DIV (timing safety)
)(
    input  wire       clk,
    input  wire       rst_n,
    output wire       ready,
    output wire       busy,
    output wire       selftest_done,   // built-in self-test finished (runs once after reset, before `ready`)
    output wire       selftest_pass,   // 1 = hardware reproduces the verified simulation exactly (valid when selftest_done)
    output reg        done,
    input  wire       cmd_start,
    input  wire       cmd_decrypt,
    input  wire       in_wr_en,
    input  wire [7:0] in_wr_addr,
    input  wire [7:0] in_wr_data,
    input  wire [7:0] out_rd_addr,
    output wire [7:0] out_rd_data
);
    // ---------------- fixed key seeds (Q16.16), part of the "key" ----------------
    localparam signed [31:0] S1_1 = 32'sd65536,  S1_2 = 32'sd131072, S1_3 = -32'sd65536, S1_4 = 32'sd32768,
                             S1_5 = 32'sd16384,  S1_6 = -32'sd32768, S1_7 = 32'sd8192,   S1_8 = 32'sd4096;
    localparam signed [31:0] S2_1 = 32'sd98304,  S2_2 = -32'sd45056, S2_3 = 32'sd20480,  S2_4 = -32'sd10240,
                             S2_5 = 32'sd51200,  S2_6 = 32'sd6144,   S2_7 = -32'sd3072,  S2_8 = 32'sd1536;
    localparam signed [31:0] S3_1 = -32'sd12345, S3_2 = 32'sd54321,  S3_3 = 32'sd9999,   S3_4 = -32'sd8888,
                             S3_5 = 32'sd7777,   S3_6 = -32'sd6666,  S3_7 = 32'sd5555,   S3_8 = -32'sd4444;

    // ---------------- clock enable for the slow sections ----------------
    // The key generator, the Process-Queue S-box builder and the Rule 30 table builder contain long combinational
    // paths (chained 32x32 multipliers, x^3 mod 257, a variable modulo).  They only change state once every CE_DIV
    // clocks, so each of those paths has CE_DIV clock periods to settle (see the multicycle constraints in mie.sdc).
    // Behaviour in "virtual cycles" is identical to running them at full speed.
    reg [7:0] ce_cnt;
    always @(posedge clk) begin
        if (!rst_n) ce_cnt <= 8'd0;
        else ce_cnt <= (ce_cnt == CE_DIV - 1) ? 8'd0 : ce_cnt + 8'd1;
    end
    wire ce = (ce_cnt == 8'd0);
    wire [7:0] rdA, rdB;          // buffer A / B read data (declared early: used by the self-test FSM)

    // ---------------- Key generator (Member 1) ----------------
    reg         key_start;
    wire        k1_rdy, k2_rdy, k3_rdy;
    wire [7:0]  k1_data, k2_data, k3_data;
    wire [7:0]  k1_addr, k2_addr, k3_addr;

    key_gen_triple u_keys (
        .clk(clk), .rst_n(rst_n), .start(key_start), .ce(ce),
        .seed1_x1(S1_1), .seed1_x2(S1_2), .seed1_x3(S1_3), .seed1_x4(S1_4),
        .seed1_x5(S1_5), .seed1_x6(S1_6), .seed1_x7(S1_7), .seed1_x8(S1_8),
        .seed2_x1(S2_1), .seed2_x2(S2_2), .seed2_x3(S2_3), .seed2_x4(S2_4),
        .seed2_x5(S2_5), .seed2_x6(S2_6), .seed2_x7(S2_7), .seed2_x8(S2_8),
        .seed3_x1(S3_1), .seed3_x2(S3_2), .seed3_x3(S3_3), .seed3_x4(S3_4),
        .seed3_x5(S3_5), .seed3_x6(S3_6), .seed3_x7(S3_7), .seed3_x8(S3_8),
        .key1_mem_ready(k1_rdy), .key1_rd_addr(k1_addr), .key1_rd_data(k1_data),
        .key2_mem_ready(k2_rdy), .key2_rd_addr(k2_addr), .key2_rd_data(k2_data),
        .key3_mem_ready(k3_rdy), .key3_rd_addr(k3_addr), .key3_rd_data(k3_data)
    );

    // ---------------- Process-Queue S-box (Member 2) ----------------
    reg          pq_start;
    reg  [1023:0] prng_bits;                 // PRNG bits taken from Key 2 (chaotic key stream)
    reg  [7:0]   pq_rd_addr;
    wire [8:0]   pq_rd_data;
    wire         pq_done, pq_busy;

    process_queue_sbox u_pq (
        .clk(clk), .reset(~rst_n), .start(pq_start), .ce(ce), .prng_bits(prng_bits),
        .sbox_rd_addr(pq_rd_addr), .sbox_rd_data(pq_rd_data),
        .done(pq_done), .busy(pq_busy)
    );

    reg [7:0] sub_lut [0:255];   // forward substitution  : plain -> cipher  (= sbox-1)
    reg [7:0] inv_sub [0:255];   // inverse substitution
    reg [7:0] inv1    [0:255];   // inverse Josephus permutation

    // ---------------- Josephus (Member 2) ----------------
    reg         jos_start;
    wire        seq_valid, seq_busy, seq_done;
    wire [8:0]  seq_val, seq_idx;

    josephus_seq_gen u_jseq (
        .clk(clk), .rst_n(rst_n), .start(jos_start), .m(JOS_M), .k(JOS_K), .x(JOS_X),
        .seq_valid(seq_valid), .seq_val(seq_val), .seq_idx(seq_idx),
        .busy(seq_busy), .done(seq_done)
    );
    always @(posedge clk) if (seq_valid) inv1[seq_val[7:0] - 8'd1] <= seq_idx[7:0];

    reg         jp_start;
    wire [8:0]  jp_din_addr;
    wire        jp_wr_en, jp_busy, jp_done;
    wire [8:0]  jp_wr_addr;
    wire [7:0]  jp_wr_data;
    wire [7:0]  src_rd_data;

    josephus_permute u_jperm (
        .clk(clk), .rst_n(rst_n),
        .seq_wr_en(seq_valid), .seq_wr_addr(seq_idx), .seq_wr_data(seq_val),
        .start(jp_start), .m(JOS_M),
        .din_addr(jp_din_addr), .din_data(src_rd_data),
        .dout_wr_en(jp_wr_en), .dout_addr(jp_wr_addr), .dout_data(jp_wr_data),
        .busy(jp_busy), .done(jp_done)
    );

    reg       cmd_dec_r;                 // direction latched at cmd_start

    // ---------------- Rule 30 stage (Member 3) ----------------
    reg         r30_build;
    wire        r30_built;
    reg         s3_start;
    wire        s3_done, s3_wr_en;
    wire [7:0]  s3_data_addr, s3_key_addr, s3_wr_addr, s3_wr_data;

    rule30_stage_top #(.CA_WIDTH(CA_WIDTH)) u_r30 (
        .clk(clk), .rst_n(rst_n), .ce(ce),
        .start_build(r30_build), .build_done(r30_built),
        .start_process(s3_start), .decrypt_mode(cmd_dec_r), .process_done(s3_done),
        .data_rd_addr(s3_data_addr), .data_rd_data(src_rd_data),
        .key_rd_addr(s3_key_addr),   .key_rd_data(k3_data),
        .out_wr_en(s3_wr_en), .out_wr_addr(s3_wr_addr), .out_wr_data(s3_wr_data)
    );

    // ---------------- generic pass engine ----------------
    reg         sp_start;
    reg  [1:0]  sp_kind;
    wire        sp_done, sp_wr_en;
    wire [7:0]  sp_src_addr, sp_aux_addr, sp_wr_addr, sp_wr_data;
    reg  [7:0]  sp_aux_data;
    reg  [2:0]  auxsel;                      // 0 K1, 1 K2, 2 sub_lut, 3 inv_sub, 4 inv1

    simple_pass u_sp (
        .clk(clk), .rst_n(rst_n), .kind(sp_kind), .start(sp_start), .done(sp_done),
        .src_rd_addr(sp_src_addr), .src_rd_data(src_rd_data),
        .aux_rd_addr(sp_aux_addr), .aux_rd_data(sp_aux_data),
        .wr_en(sp_wr_en), .wr_addr(sp_wr_addr), .wr_data(sp_wr_data)
    );

    always @(*) begin
        case (auxsel)
            3'd0:    sp_aux_data = k1_data;
            3'd1:    sp_aux_data = k2_data;
            3'd2:    sp_aux_data = sub_lut[sp_aux_addr];
            3'd3:    sp_aux_data = inv_sub[sp_aux_addr];
            default: sp_aux_data = inv1[sp_aux_addr];
        endcase
    end

    // ---------------- sequencer ----------------
    localparam I_WAIT0 = 5'd0,  I_KEYS  = 5'd1,  I_KEYW  = 5'd2,  I_LDA   = 5'd3,  I_LDC   = 5'd4,
               I_PQ    = 5'd5,  I_PQW   = 5'd6,  I_SUBA  = 5'd7,  I_SUBW  = 5'd8,
               I_JOS   = 5'd9,  I_JOSW  = 5'd10, I_R30   = 5'd11, I_R30W  = 5'd12,
               R_IDLE  = 5'd13, R_START = 5'd14, R_WAIT  = 5'd15, R_NEXT  = 5'd16, R_GAP = 5'd17,
               T_FILL  = 5'd18, T_ENC0  = 5'd19, T_CMP1  = 5'd20, T_COPY  = 5'd21, T_DEC0  = 5'd22, T_CMP2 = 5'd23, T_END = 5'd24;
    reg [4:0] st;
    reg [7:0] cnt;
    reg [2:0] step;

    // which unit is active in the current step
    localparam U_SP = 2'd0, U_JP = 2'd1, U_S3 = 2'd2;
    reg [1:0] unit;
    reg       src_sel, dst_sel;               // 0 = buffer A, 1 = buffer B
    always @(*) begin
        unit = U_SP; sp_kind = 2'd0; auxsel = 3'd0; src_sel = 1'b0; dst_sel = 1'b1;
        if (!cmd_dec_r) begin
            case (step)
                3'd0: begin unit = U_SP; sp_kind = 2'd0; auxsel = 3'd0; src_sel = 0; dst_sel = 1; end
                3'd1: begin unit = U_JP;                                src_sel = 1; dst_sel = 0; end
                3'd2: begin unit = U_SP; sp_kind = 2'd0; auxsel = 3'd1; src_sel = 0; dst_sel = 1; end
                3'd3: begin unit = U_SP; sp_kind = 2'd1; auxsel = 3'd2; src_sel = 1; dst_sel = 0; end
                default: begin unit = U_S3;                             src_sel = 0; dst_sel = 1; end
            endcase
        end else begin
            case (step)
                3'd0: begin unit = U_S3;                                src_sel = 0; dst_sel = 1; end
                3'd1: begin unit = U_SP; sp_kind = 2'd1; auxsel = 3'd3; src_sel = 1; dst_sel = 0; end
                3'd2: begin unit = U_SP; sp_kind = 2'd0; auxsel = 3'd1; src_sel = 0; dst_sel = 1; end
                3'd3: begin unit = U_SP; sp_kind = 2'd2; auxsel = 3'd4; src_sel = 1; dst_sel = 0; end
                default: begin unit = U_SP; sp_kind = 2'd0; auxsel = 3'd0; src_sel = 0; dst_sel = 1; end
            endcase
        end
    end

    wire unit_done = (unit == U_SP) ? sp_done : (unit == U_JP) ? jp_done : s3_done;

    reg        inited, selftest_done_r, enc_ok, rt_ok, tst_on, tst_dec_phase, tst_we;
    reg  [8:0] tcnt;
    reg  [7:0] tst_wa, tst_wd;
    assign ready = inited;
    assign busy  = (st != R_IDLE);
    assign selftest_done = selftest_done_r;
    assign selftest_pass = enc_ok & rt_ok;
    // golden ciphertext of the self-test block (pattern (29*j+3) mod 256), produced by the verified simulation
    function [7:0] gold(input [7:0] j);
        case (j)
            8'd0: gold = 8'hc9;
            8'd1: gold = 8'h01;
            8'd2: gold = 8'hd3;
            8'd3: gold = 8'h0f;
            8'd4: gold = 8'h6c;
            8'd5: gold = 8'hed;
            8'd6: gold = 8'hb4;
            8'd7: gold = 8'hdd;
            8'd8: gold = 8'h3b;
            8'd9: gold = 8'h9e;
            8'd10: gold = 8'h3e;
            8'd11: gold = 8'h0f;
            8'd12: gold = 8'hdc;
            8'd13: gold = 8'h9b;
            8'd14: gold = 8'h90;
            8'd15: gold = 8'h0c;
            8'd16: gold = 8'h5e;
            8'd17: gold = 8'hae;
            8'd18: gold = 8'hfd;
            8'd19: gold = 8'h17;
            8'd20: gold = 8'h5c;
            8'd21: gold = 8'h22;
            8'd22: gold = 8'h3e;
            8'd23: gold = 8'h2c;
            8'd24: gold = 8'hde;
            8'd25: gold = 8'h36;
            8'd26: gold = 8'hfb;
            8'd27: gold = 8'h2a;
            8'd28: gold = 8'hc0;
            8'd29: gold = 8'h20;
            8'd30: gold = 8'h58;
            8'd31: gold = 8'hcf;
            8'd32: gold = 8'hc8;
            8'd33: gold = 8'h80;
            8'd34: gold = 8'h32;
            8'd35: gold = 8'h7b;
            8'd36: gold = 8'h6a;
            8'd37: gold = 8'h52;
            8'd38: gold = 8'hac;
            8'd39: gold = 8'h33;
            8'd40: gold = 8'he4;
            8'd41: gold = 8'h0a;
            8'd42: gold = 8'h00;
            8'd43: gold = 8'h12;
            8'd44: gold = 8'hd4;
            8'd45: gold = 8'haa;
            8'd46: gold = 8'hfc;
            8'd47: gold = 8'h40;
            8'd48: gold = 8'h74;
            8'd49: gold = 8'h54;
            8'd50: gold = 8'h3b;
            8'd51: gold = 8'h42;
            8'd52: gold = 8'h9c;
            8'd53: gold = 8'h9f;
            8'd54: gold = 8'h98;
            8'd55: gold = 8'h88;
            8'd56: gold = 8'h22;
            8'd57: gold = 8'haa;
            8'd58: gold = 8'h94;
            8'd59: gold = 8'h2c;
            8'd60: gold = 8'h6c;
            8'd61: gold = 8'hdd;
            8'd62: gold = 8'h91;
            8'd63: gold = 8'h87;
            8'd64: gold = 8'h68;
            8'd65: gold = 8'h72;
            8'd66: gold = 8'h6f;
            8'd67: gold = 8'he4;
            8'd68: gold = 8'hb9;
            8'd69: gold = 8'h85;
            8'd70: gold = 8'hee;
            8'd71: gold = 8'h42;
            8'd72: gold = 8'h8a;
            8'd73: gold = 8'hbe;
            8'd74: gold = 8'h7a;
            8'd75: gold = 8'h50;
            8'd76: gold = 8'hdb;
            8'd77: gold = 8'hc1;
            8'd78: gold = 8'h96;
            8'd79: gold = 8'hf7;
            8'd80: gold = 8'hcc;
            8'd81: gold = 8'h5b;
            8'd82: gold = 8'hd6;
            8'd83: gold = 8'h50;
            8'd84: gold = 8'h9d;
            8'd85: gold = 8'he6;
            8'd86: gold = 8'h47;
            8'd87: gold = 8'hc0;
            8'd88: gold = 8'h39;
            8'd89: gold = 8'h8f;
            8'd90: gold = 8'h76;
            8'd91: gold = 8'h2e;
            8'd92: gold = 8'h6f;
            8'd93: gold = 8'hbf;
            8'd94: gold = 8'h20;
            8'd95: gold = 8'h05;
            8'd96: gold = 8'hf7;
            8'd97: gold = 8'h74;
            8'd98: gold = 8'hc2;
            8'd99: gold = 8'h72;
            8'd100: gold = 8'h2e;
            8'd101: gold = 8'hd4;
            8'd102: gold = 8'h5f;
            8'd103: gold = 8'h68;
            8'd104: gold = 8'h57;
            8'd105: gold = 8'h68;
            8'd106: gold = 8'h43;
            8'd107: gold = 8'h9e;
            8'd108: gold = 8'hd3;
            8'd109: gold = 8'hd3;
            8'd110: gold = 8'h0c;
            8'd111: gold = 8'h13;
            8'd112: gold = 8'h34;
            8'd113: gold = 8'h9f;
            8'd114: gold = 8'h7e;
            8'd115: gold = 8'h3b;
            8'd116: gold = 8'h0d;
            8'd117: gold = 8'ha9;
            8'd118: gold = 8'hd3;
            8'd119: gold = 8'hc8;
            8'd120: gold = 8'h40;
            8'd121: gold = 8'h51;
            8'd122: gold = 8'h94;
            8'd123: gold = 8'hba;
            8'd124: gold = 8'h56;
            8'd125: gold = 8'h83;
            8'd126: gold = 8'hdc;
            8'd127: gold = 8'h5b;
            8'd128: gold = 8'h28;
            8'd129: gold = 8'hd5;
            8'd130: gold = 8'h17;
            8'd131: gold = 8'h5a;
            8'd132: gold = 8'h82;
            8'd133: gold = 8'hf9;
            8'd134: gold = 8'h60;
            8'd135: gold = 8'ha3;
            8'd136: gold = 8'ha3;
            8'd137: gold = 8'h91;
            8'd138: gold = 8'hc2;
            8'd139: gold = 8'ha2;
            8'd140: gold = 8'h61;
            8'd141: gold = 8'h36;
            8'd142: gold = 8'h4a;
            8'd143: gold = 8'he9;
            8'd144: gold = 8'h69;
            8'd145: gold = 8'h51;
            8'd146: gold = 8'h33;
            8'd147: gold = 8'h4e;
            8'd148: gold = 8'hc7;
            8'd149: gold = 8'h05;
            8'd150: gold = 8'heb;
            8'd151: gold = 8'h56;
            8'd152: gold = 8'h41;
            8'd153: gold = 8'ha7;
            8'd154: gold = 8'hea;
            8'd155: gold = 8'h40;
            8'd156: gold = 8'h71;
            8'd157: gold = 8'h69;
            8'd158: gold = 8'hd6;
            8'd159: gold = 8'hdf;
            8'd160: gold = 8'he7;
            8'd161: gold = 8'hff;
            8'd162: gold = 8'hc1;
            8'd163: gold = 8'h51;
            8'd164: gold = 8'hfb;
            8'd165: gold = 8'h50;
            8'd166: gold = 8'h65;
            8'd167: gold = 8'h2c;
            8'd168: gold = 8'ha5;
            8'd169: gold = 8'h83;
            8'd170: gold = 8'h4a;
            8'd171: gold = 8'h36;
            8'd172: gold = 8'hf0;
            8'd173: gold = 8'h54;
            8'd174: gold = 8'h63;
            8'd175: gold = 8'h40;
            8'd176: gold = 8'ha9;
            8'd177: gold = 8'h7c;
            8'd178: gold = 8'h52;
            8'd179: gold = 8'hc2;
            8'd180: gold = 8'hf2;
            8'd181: gold = 8'h33;
            8'd182: gold = 8'hf4;
            8'd183: gold = 8'h90;
            8'd184: gold = 8'hfc;
            8'd185: gold = 8'h54;
            8'd186: gold = 8'h68;
            8'd187: gold = 8'h25;
            8'd188: gold = 8'h28;
            8'd189: gold = 8'h7e;
            8'd190: gold = 8'hc8;
            8'd191: gold = 8'h63;
            8'd192: gold = 8'hab;
            8'd193: gold = 8'h86;
            8'd194: gold = 8'hb3;
            8'd195: gold = 8'h7c;
            8'd196: gold = 8'h99;
            8'd197: gold = 8'hf4;
            8'd198: gold = 8'h1a;
            8'd199: gold = 8'hb5;
            8'd200: gold = 8'h98;
            8'd201: gold = 8'h49;
            8'd202: gold = 8'h9f;
            8'd203: gold = 8'h7c;
            8'd204: gold = 8'h1b;
            8'd205: gold = 8'h43;
            8'd206: gold = 8'hb3;
            8'd207: gold = 8'hf4;
            8'd208: gold = 8'hc2;
            8'd209: gold = 8'he8;
            8'd210: gold = 8'hb0;
            8'd211: gold = 8'h62;
            8'd212: gold = 8'h4f;
            8'd213: gold = 8'hf5;
            8'd214: gold = 8'h56;
            8'd215: gold = 8'h1a;
            8'd216: gold = 8'hcd;
            8'd217: gold = 8'ha3;
            8'd218: gold = 8'h7e;
            8'd219: gold = 8'h6f;
            8'd220: gold = 8'hcd;
            8'd221: gold = 8'h9a;
            8'd222: gold = 8'h0b;
            8'd223: gold = 8'hde;
            8'd224: gold = 8'h2f;
            8'd225: gold = 8'h43;
            8'd226: gold = 8'hf9;
            8'd227: gold = 8'ha5;
            8'd228: gold = 8'h47;
            8'd229: gold = 8'hba;
            8'd230: gold = 8'h17;
            8'd231: gold = 8'h8a;
            8'd232: gold = 8'h44;
            8'd233: gold = 8'h0e;
            8'd234: gold = 8'h48;
            8'd235: gold = 8'hb0;
            8'd236: gold = 8'h18;
            8'd237: gold = 8'hdf;
            8'd238: gold = 8'h72;
            8'd239: gold = 8'h28;
            8'd240: gold = 8'h20;
            8'd241: gold = 8'h72;
            8'd242: gold = 8'hc9;
            8'd243: gold = 8'h36;
            8'd244: gold = 8'hee;
            8'd245: gold = 8'h6b;
            8'd246: gold = 8'hc7;
            8'd247: gold = 8'hbb;
            8'd248: gold = 8'h24;
            8'd249: gold = 8'h3b;
            8'd250: gold = 8'hde;
            8'd251: gold = 8'hfa;
            8'd252: gold = 8'h6e;
            8'd253: gold = 8'hf6;
            8'd254: gold = 8'h9f;
            8'd255: gold = 8'hd5;
            default: gold = 8'h00;
        endcase
    endfunction
    function [7:0] pat(input [7:0] j);
        reg [15:0] t;
        begin t = j * 8'd29 + 8'd3; pat = t[7:0]; end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= I_WAIT0; cnt <= 8'd0; step <= 3'd0; done <= 1'b0; cmd_dec_r <= 1'b0;
            key_start <= 1'b0; pq_start <= 1'b0; jos_start <= 1'b0; r30_build <= 1'b0;
            sp_start <= 1'b0; jp_start <= 1'b0; s3_start <= 1'b0;
            prng_bits <= {1024{1'b0}}; pq_rd_addr <= 8'd0;
            inited <= 1'b0; selftest_done_r <= 1'b0; enc_ok <= 1'b1; rt_ok <= 1'b1; tst_on <= 1'b0; tst_dec_phase <= 1'b0;
            tst_we <= 1'b0; tcnt <= 9'd0; tst_wa <= 8'd0; tst_wd <= 8'd0;
        end else begin
            key_start <= 1'b0; pq_start <= 1'b0; jos_start <= 1'b0; r30_build <= 1'b0;
            sp_start <= 1'b0; jp_start <= 1'b0; s3_start <= 1'b0; tst_we <= 1'b0;
            case (st)
                // ---------- initialisation (runs once after reset, fixed cycle timing) ----------
                I_WAIT0: begin st <= I_KEYS; end
                I_KEYS:  begin key_start <= 1'b1; st <= I_KEYW; end
                I_KEYW:  if (k1_rdy && k2_rdy && k3_rdy) begin cnt <= 8'd0; st <= I_LDA; end
                I_LDA:   st <= I_LDC;                                   // key2 address presented
                I_LDC:   begin                                          // registered key2 data valid
                             prng_bits[{cnt[6:0], 3'b000} +: 8] <= k2_data;
                             if (cnt == 8'd127) begin cnt <= 8'd0; st <= I_PQ; end
                             else begin cnt <= cnt + 8'd1; st <= I_LDA; end
                         end
                I_PQ:    begin pq_start <= 1'b1; st <= I_PQW; end
                I_PQW:   if (pq_done) begin cnt <= 8'd0; st <= I_SUBA; end
                I_SUBA:  begin pq_rd_addr <= cnt; st <= I_SUBW; end
                I_SUBW:  begin
                             sub_lut[cnt]                    <= pq_rd_data[7:0] - 8'd1;
                             inv_sub[pq_rd_data[7:0] - 8'd1] <= cnt;
                             if (cnt == 8'd255) st <= I_JOS;
                             else begin cnt <= cnt + 8'd1; st <= I_SUBA; end
                         end
                I_JOS:   begin jos_start <= 1'b1; st <= I_JOSW; end
                I_JOSW:  if (seq_done) st <= I_R30;
                I_R30:   begin r30_build <= 1'b1; st <= I_R30W; end
                I_R30W:  if (r30_built) begin tcnt <= 9'd0; enc_ok <= 1'b1; rt_ok <= 1'b1; tst_on <= 1'b1; tst_dec_phase <= 1'b0; st <= T_FILL; end
                // ---------- block processing ----------
                R_IDLE:  if (cmd_start) begin
                             cmd_dec_r <= cmd_decrypt; done <= 1'b0; step <= 3'd0; st <= R_START;
                         end
                R_START: begin
                             sp_start <= (unit == U_SP);
                             jp_start <= (unit == U_JP);
                             s3_start <= (unit == U_S3);
                             st <= R_GAP;      // start pulse is visible during R_GAP; the unit clears its
                         end                   // old 'done' at the end of it, so R_WAIT never sees stale done
                R_GAP:   st <= R_WAIT;
                R_WAIT:  if (unit_done) st <= R_NEXT;
                R_NEXT:  begin
                             if (step == 3'd4) begin
                                 if (tst_on) begin tcnt <= 9'd0; st <= tst_dec_phase ? T_CMP2 : T_CMP1; end
                                 else begin done <= 1'b1; st <= R_IDLE; end
                             end
                             else begin step <= step + 3'd1; st <= R_START; end
                         end
                // ---------- built-in self-test (runs once, between initialisation and `ready`) ----------
                T_FILL:  begin tst_we <= 1'b1; tst_wa <= tcnt[7:0]; tst_wd <= pat(tcnt[7:0]);
                               if (tcnt == 9'd255) begin tcnt <= 9'd0; st <= T_ENC0; end else tcnt <= tcnt + 9'd1; end
                T_ENC0:  begin cmd_dec_r <= 1'b0; tst_dec_phase <= 1'b0; step <= 3'd0; st <= R_START; end
                T_CMP1:  begin if (rdB != gold(tcnt[7:0])) enc_ok <= 1'b0;
                               if (tcnt == 9'd255) begin tcnt <= 9'd0; st <= T_COPY; end else tcnt <= tcnt + 9'd1; end
                T_COPY:  begin tst_we <= 1'b1; tst_wa <= tcnt[7:0]; tst_wd <= rdB;
                               if (tcnt == 9'd255) begin tcnt <= 9'd0; st <= T_DEC0; end else tcnt <= tcnt + 9'd1; end
                T_DEC0:  begin cmd_dec_r <= 1'b1; tst_dec_phase <= 1'b1; step <= 3'd0; st <= R_START; end
                T_CMP2:  begin if (rdB != pat(tcnt[7:0])) rt_ok <= 1'b0;
                               if (tcnt == 9'd255) st <= T_END; else tcnt <= tcnt + 9'd1; end
                T_END:   begin tst_on <= 1'b0; inited <= 1'b1; selftest_done_r <= 1'b1; done <= 1'b0; st <= R_IDLE; end
                default: st <= I_WAIT0;
            endcase
        end
    end

    // ---------------- block buffers & muxing ----------------
    wire        act_we   = (unit == U_SP) ? sp_wr_en : (unit == U_JP) ? jp_wr_en : s3_wr_en;
    wire [7:0]  act_wa   = (unit == U_SP) ? sp_wr_addr : (unit == U_JP) ? jp_wr_addr[7:0] : s3_wr_addr;
    wire [7:0]  act_wd   = (unit == U_SP) ? sp_wr_data : (unit == U_JP) ? jp_wr_data : s3_wr_data;
    wire [7:0]  act_ra   = (unit == U_SP) ? sp_src_addr : (unit == U_JP) ? jp_din_addr[7:0] : s3_data_addr;
    wire        running  = (st == R_START) || (st == R_GAP) || (st == R_WAIT) || (st == R_NEXT);
    wire        host_wr  = ((st == R_IDLE) && in_wr_en) | tst_we;
    wire [7:0]  h_wa     = tst_we ? tst_wa : in_wr_addr;
    wire [7:0]  h_wd     = tst_we ? tst_wd : in_wr_data;
    wire        tst_rd   = (st == T_CMP1) || (st == T_COPY) || (st == T_CMP2);

    blk_ram u_bufA (.clk(clk),
        .we(host_wr | (running & act_we & ~dst_sel)),
        .waddr(host_wr ? h_wa : act_wa), .wdata(host_wr ? h_wd : act_wd),
        .raddr(act_ra), .rdata(rdA));
    blk_ram u_bufB (.clk(clk),
        .we(running & act_we & dst_sel),
        .waddr(act_wa), .wdata(act_wd),
        .raddr(running ? act_ra : (tst_rd ? tcnt[7:0] : out_rd_addr)), .rdata(rdB));

    assign src_rd_data = (running ? src_sel : 1'b1) ? rdB : rdA;
    assign out_rd_data = rdB;

    // key memory read addresses
    assign k1_addr = sp_aux_addr;
    assign k2_addr = (st == I_LDA || st == I_LDC) ? {1'b0, cnt[6:0]} : sp_aux_addr;
    assign k3_addr = s3_key_addr;
endmodule
