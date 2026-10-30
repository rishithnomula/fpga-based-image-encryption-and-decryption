// =============================================================
// rule30_stage_top.v   (Member 3 sub-top: "Stage 3 engine")
// -------------------------------------------------------------
// Combines, with no changes to the originals:
//   rule30_shuffle_engine   -> forward S-box (FWD)
//   rule30_inverse_builder  -> inverse S-box (INV)
//   stage_process           -> fused XOR + permute (enc or dec)
//
// Usage:
//   1. Pulse start_build once after reset.
//      Builds FWD, then INV.  build_done goes high when both are ready.
//   2. Set decrypt_mode (0 = encrypt, 1 = decrypt), then pulse
//      start_process.  process_done goes high when the 256-byte
//      block has been written out.
//   3. To process another block, change data/key/mode and pulse
//      start_process again .
//
// The data block, key block and output block live OUTSIDE this
// module (img2bits / key memory / bits2img or next stage), so the
// same top can be reused for encrypt and decrypt.
//
// NOTE 1: rule30_shuffle_engine and rule30_inverse_builder stay in
//   DONE until rst_n (fine: tables are built once).  stage_process
//   here is the modified copy whose S_DONE accepts a new 'start',
//   so blocks can be processed back to back, encrypt or decrypt.
// =============================================================

module rule30_stage_top #(
    parameter CA_WIDTH = 4593
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ce,             // clock enable for the table-build section

    // ---- S-box build control ----
    input  wire       start_build,
    output wire       build_done,

    // ---- block processing control ----
    input  wire       start_process,
    input  wire       decrypt_mode,   // 0 = encrypt, 1 = decrypt
    output wire       process_done,

    // ---- external data block (read) ----
    output wire [7:0] data_rd_addr,
    input  wire [7:0] data_rd_data,

    // ---- external key block (read) ----
    output wire [7:0] key_rd_addr,
    input  wire [7:0] key_rd_data,

    // ---- external output block (write) ----
    output wire       out_wr_en,
    output wire [7:0] out_wr_addr,
    output wire [7:0] out_wr_data
);

    // ---------------------------------------------------------
    // Build sequencer: FWD first, then INV
    // ---------------------------------------------------------
    localparam B_IDLE  = 2'd0,
               B_FWD   = 2'd1,
               B_INV   = 2'd2,
               B_READY = 2'd3;

    reg [1:0] b_state;
    reg       build_p;      // start_build latched until the next clock-enable tick
    always @(posedge clk) begin
        if (!rst_n) build_p <= 1'b0;
        else if (start_build) build_p <= 1'b1;
        else if (ce) build_p <= 1'b0;
    end
    reg       fwd_start, inv_start;
    wire      fwd_done,  inv_done;

    always @(posedge clk) begin
        if (!rst_n) begin
            b_state   <= B_IDLE;
            fwd_start <= 1'b0;
            inv_start <= 1'b0;
        end else if (ce) begin
            fwd_start <= 1'b0;   // one-cycle pulses
            inv_start <= 1'b0;

            case (b_state)
                B_IDLE:  if (build_p) begin
                             fwd_start <= 1'b1;
                             b_state   <= B_FWD;
                         end
                B_FWD:   if (fwd_done) begin
                             inv_start <= 1'b1;
                             b_state   <= B_INV;
                         end
                B_INV:   if (inv_done)
                             b_state   <= B_READY;
                B_READY: ;   // stay until reset
                default: b_state <= B_IDLE;
            endcase
        end
    end

    assign build_done = (b_state == B_READY);

    // ---------------------------------------------------------
    // Forward S-box: read port shared between the inverse builder
    // (while building INV) and stage_process (while encrypting)
    // ---------------------------------------------------------
    wire [7:0] fwd_rd_addr;
    wire [7:0] fwd_rd_data;
    wire [7:0] inv_build_fwd_addr;   // from inverse builder
    wire [7:0] stg_table_addr;       // from stage_process

    assign fwd_rd_addr = (b_state == B_INV) ? inv_build_fwd_addr
                                            : stg_table_addr;

    rule30_shuffle_engine #(.CA_WIDTH(CA_WIDTH)) fwd_sbox (
        .clk(clk), .rst_n(rst_n), .ce(ce),
        .start(fwd_start), .done(fwd_done),
        .rd_addr(fwd_rd_addr), .rd_data(fwd_rd_data)
    );

    // ---------------------------------------------------------
    // Inverse S-box: read port used only by stage_process (decrypt)
    // ---------------------------------------------------------
    wire [7:0] inv_rd_data;

    rule30_inverse_builder inv_sbox (
        .clk(clk), .rst_n(rst_n), .ce(ce),
        .start(inv_start), .done(inv_done),
        .fwd_rd_addr(inv_build_fwd_addr), .fwd_rd_data(fwd_rd_data),
        .inv_rd_addr(stg_table_addr),     .inv_rd_data(inv_rd_data)
    );

    // ---------------------------------------------------------
    // XOR + permute engine; table source picked by mode
    // ---------------------------------------------------------
    wire [7:0] stg_table_data = decrypt_mode ? inv_rd_data : fwd_rd_data;
    wire       stg_start      = start_process & build_done;  // ignore until tables are ready

    stage_process stage (
        .clk(clk), .rst_n(rst_n),
        .start(stg_start), .decrypt_mode(decrypt_mode), .done(process_done),
        .table_rd_addr(stg_table_addr), .table_rd_data(stg_table_data),
        .data_rd_addr(data_rd_addr),    .data_rd_data(data_rd_data),
        .key_rd_addr(key_rd_addr),      .key_rd_data(key_rd_data),
        .out_wr_en(out_wr_en), .out_wr_addr(out_wr_addr), .out_wr_data(out_wr_data)
    );

endmodule
