
module chaotic8d_core (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                ce,         // clock enable: slow section, paths get CE_DIV clocks to settle
    input  wire                load_seed,  // pulse 1 cycle to load initial conditions
    input  wire signed [31:0]  seed_x1,
    input  wire signed [31:0]  seed_x2,
    input  wire signed [31:0]  seed_x3,
    input  wire signed [31:0]  seed_x4,
    input  wire signed [31:0]  seed_x5,
    input  wire signed [31:0]  seed_x6,
    input  wire signed [31:0]  seed_x7,
    input  wire signed [31:0]  seed_x8,
    output wire signed [31:0]  x1,
    output wire signed [31:0]  x2,
    output wire signed [31:0]  x3,
    output wire signed [31:0]  x4,
    output wire signed [31:0]  x5,
    output wire signed [31:0]  x6,
    output wire signed [31:0]  x7,
    output wire signed [31:0]  x8,
    output wire                valid       // pulses 1 cycle per completed RK4 step
);

    localparam signed [31:0] DT       = 32'sd12; // ~0.000183 (full step)
    localparam signed [31:0] DT_HALF  = 32'sd6;  // exactly DT/2
    localparam signed [31:0] DT_SIXTH = 32'sd2;  // exactly DT/6
    localparam signed [31:0] STATE_CLAMP = 32'sd1310720000; // 20000.0

  
    localparam [2:0] S_K1     = 3'd0;
    localparam [2:0] S_K2     = 3'd1;
    localparam [2:0] S_K3     = 3'd2;
    localparam [2:0] S_K4     = 3'd3;
    localparam [2:0] S_UPDATE = 3'd4;

    reg [2:0] state;
    reg signed [31:0] rx1, rx2, rx3, rx4, rx5, rx6, rx7, rx8;
    reg               valid_reg;


    reg signed [31:0] k1_1, k1_2, k1_3, k1_4, k1_5, k1_6, k1_7, k1_8;
    reg signed [31:0] k2_1, k2_2, k2_3, k2_4, k2_5, k2_6, k2_7, k2_8;
    reg signed [31:0] k3_1, k3_2, k3_3, k3_4, k3_5, k3_6, k3_7, k3_8;
    reg signed [31:0] k4_1, k4_2, k4_3, k4_4, k4_5, k4_6, k4_7, k4_8;

  
    wire signed [31:0] scale_sel;
    assign scale_sel = (state == S_K2 || state == S_K3) ? DT_HALF :
                        (state == S_K4)                  ? DT      :
                                                            32'sd0;

    wire signed [31:0] kprev_1 = (state == S_K2) ? k1_1 : (state == S_K3) ? k2_1 : (state == S_K4) ? k3_1 : 32'sd0;
    wire signed [31:0] kprev_2 = (state == S_K2) ? k1_2 : (state == S_K3) ? k2_2 : (state == S_K4) ? k3_2 : 32'sd0;
    wire signed [31:0] kprev_3 = (state == S_K2) ? k1_3 : (state == S_K3) ? k2_3 : (state == S_K4) ? k3_3 : 32'sd0;
    wire signed [31:0] kprev_4 = (state == S_K2) ? k1_4 : (state == S_K3) ? k2_4 : (state == S_K4) ? k3_4 : 32'sd0;
    wire signed [31:0] kprev_5 = (state == S_K2) ? k1_5 : (state == S_K3) ? k2_5 : (state == S_K4) ? k3_5 : 32'sd0;
    wire signed [31:0] kprev_6 = (state == S_K2) ? k1_6 : (state == S_K3) ? k2_6 : (state == S_K4) ? k3_6 : 32'sd0;
    wire signed [31:0] kprev_7 = (state == S_K2) ? k1_7 : (state == S_K3) ? k2_7 : (state == S_K4) ? k3_7 : 32'sd0;
    wire signed [31:0] kprev_8 = (state == S_K2) ? k1_8 : (state == S_K3) ? k2_8 : (state == S_K4) ? k3_8 : 32'sd0;

    wire signed [31:0] scaled_1, scaled_2, scaled_3, scaled_4, scaled_5, scaled_6, scaled_7, scaled_8;
    fixed_mult u_scale1 (.a(scale_sel), .b(kprev_1), .result(scaled_1));
    fixed_mult u_scale2 (.a(scale_sel), .b(kprev_2), .result(scaled_2));
    fixed_mult u_scale3 (.a(scale_sel), .b(kprev_3), .result(scaled_3));
    fixed_mult u_scale4 (.a(scale_sel), .b(kprev_4), .result(scaled_4));
    fixed_mult u_scale5 (.a(scale_sel), .b(kprev_5), .result(scaled_5));
    fixed_mult u_scale6 (.a(scale_sel), .b(kprev_6), .result(scaled_6));
    fixed_mult u_scale7 (.a(scale_sel), .b(kprev_7), .result(scaled_7));
    fixed_mult u_scale8 (.a(scale_sel), .b(kprev_8), .result(scaled_8));

    wire signed [31:0] dxin_1 = rx1 + scaled_1;
    wire signed [31:0] dxin_2 = rx2 + scaled_2;
    wire signed [31:0] dxin_3 = rx3 + scaled_3;
    wire signed [31:0] dxin_4 = rx4 + scaled_4;
    wire signed [31:0] dxin_5 = rx5 + scaled_5;
    wire signed [31:0] dxin_6 = rx6 + scaled_6;
    wire signed [31:0] dxin_7 = rx7 + scaled_7;
    wire signed [31:0] dxin_8 = rx8 + scaled_8;

    wire signed [31:0] d1, d2, d3, d4, d5, d6, d7, d8;

    derivative_function u_deriv (
        .x1(dxin_1), .x2(dxin_2), .x3(dxin_3), .x4(dxin_4),
        .x5(dxin_5), .x6(dxin_6), .x7(dxin_7), .x8(dxin_8),
        .dx1(d1), .dx2(d2), .dx3(d3), .dx4(d4),
        .dx5(d5), .dx6(d6), .dx7(d7), .dx8(d8)
    );


    wire signed [31:0] sum_1 = k1_1 + (k2_1 <<< 1) + (k3_1 <<< 1) + k4_1;
    wire signed [31:0] sum_2 = k1_2 + (k2_2 <<< 1) + (k3_2 <<< 1) + k4_2;
    wire signed [31:0] sum_3 = k1_3 + (k2_3 <<< 1) + (k3_3 <<< 1) + k4_3;
    wire signed [31:0] sum_4 = k1_4 + (k2_4 <<< 1) + (k3_4 <<< 1) + k4_4;
    wire signed [31:0] sum_5 = k1_5 + (k2_5 <<< 1) + (k3_5 <<< 1) + k4_5;
    wire signed [31:0] sum_6 = k1_6 + (k2_6 <<< 1) + (k3_6 <<< 1) + k4_6;
    wire signed [31:0] sum_7 = k1_7 + (k2_7 <<< 1) + (k3_7 <<< 1) + k4_7;
    wire signed [31:0] sum_8 = k1_8 + (k2_8 <<< 1) + (k3_8 <<< 1) + k4_8;

    wire signed [31:0] weighted_1, weighted_2, weighted_3, weighted_4;
    wire signed [31:0] weighted_5, weighted_6, weighted_7, weighted_8;
    fixed_mult u_w1 (.a(DT_SIXTH), .b(sum_1), .result(weighted_1));
    fixed_mult u_w2 (.a(DT_SIXTH), .b(sum_2), .result(weighted_2));
    fixed_mult u_w3 (.a(DT_SIXTH), .b(sum_3), .result(weighted_3));
    fixed_mult u_w4 (.a(DT_SIXTH), .b(sum_4), .result(weighted_4));
    fixed_mult u_w5 (.a(DT_SIXTH), .b(sum_5), .result(weighted_5));
    fixed_mult u_w6 (.a(DT_SIXTH), .b(sum_6), .result(weighted_6));
    fixed_mult u_w7 (.a(DT_SIXTH), .b(sum_7), .result(weighted_7));
    fixed_mult u_w8 (.a(DT_SIXTH), .b(sum_8), .result(weighted_8));

    wire signed [31:0] new_rx1 = rx1 + weighted_1;
    wire signed [31:0] new_rx2 = rx2 + weighted_2;
    wire signed [31:0] new_rx3 = rx3 + weighted_3;
    wire signed [31:0] new_rx4 = rx4 + weighted_4;
    wire signed [31:0] new_rx5 = rx5 + weighted_5;
    wire signed [31:0] new_rx6 = rx6 + weighted_6;
    wire signed [31:0] new_rx7 = rx7 + weighted_7;
    wire signed [31:0] new_rx8 = rx8 + weighted_8;

    // ---------------------------------------------------------
    // FSM sequencing
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            rx1 <= 32'sd0; rx2 <= 32'sd0; rx3 <= 32'sd0; rx4 <= 32'sd0;
            rx5 <= 32'sd0; rx6 <= 32'sd0; rx7 <= 32'sd0; rx8 <= 32'sd0;
            state     <= S_K1;
            valid_reg <= 1'b0;
        end else if (!ce) begin
            // hold
        end else if (load_seed) begin
            rx1 <= seed_x1; rx2 <= seed_x2; rx3 <= seed_x3; rx4 <= seed_x4;
            rx5 <= seed_x5; rx6 <= seed_x6; rx7 <= seed_x7; rx8 <= seed_x8;
            state     <= S_K1;
            valid_reg <= 1'b0;
        end else begin
            valid_reg <= 1'b0;

            case (state)
                S_K1: begin
                    k1_1 <= d1; k1_2 <= d2; k1_3 <= d3; k1_4 <= d4;
                    k1_5 <= d5; k1_6 <= d6; k1_7 <= d7; k1_8 <= d8;
                    state <= S_K2;
                end

                S_K2: begin
                    k2_1 <= d1; k2_2 <= d2; k2_3 <= d3; k2_4 <= d4;
                    k2_5 <= d5; k2_6 <= d6; k2_7 <= d7; k2_8 <= d8;
                    state <= S_K3;
                end

                S_K3: begin
                    k3_1 <= d1; k3_2 <= d2; k3_3 <= d3; k3_4 <= d4;
                    k3_5 <= d5; k3_6 <= d6; k3_7 <= d7; k3_8 <= d8;
                    state <= S_K4;
                end

                S_K4: begin
                    k4_1 <= d1; k4_2 <= d2; k4_3 <= d3; k4_4 <= d4;
                    k4_5 <= d5; k4_6 <= d6; k4_7 <= d7; k4_8 <= d8;
                    state <= S_UPDATE;
                end

                S_UPDATE: begin
                    
                    rx1 <= (new_rx1 >  STATE_CLAMP) ?  STATE_CLAMP :
                           (new_rx1 < -STATE_CLAMP) ? -STATE_CLAMP : new_rx1;
                    rx2 <= (new_rx2 >  STATE_CLAMP) ?  STATE_CLAMP :
                           (new_rx2 < -STATE_CLAMP) ? -STATE_CLAMP : new_rx2;
                    rx3 <= (new_rx3 >  STATE_CLAMP) ?  STATE_CLAMP :
                           (new_rx3 < -STATE_CLAMP) ? -STATE_CLAMP : new_rx3;
                    rx4 <= (new_rx4 >  STATE_CLAMP) ?  STATE_CLAMP :
                           (new_rx4 < -STATE_CLAMP) ? -STATE_CLAMP : new_rx4;
                    rx5 <= (new_rx5 >  STATE_CLAMP) ?  STATE_CLAMP :
                           (new_rx5 < -STATE_CLAMP) ? -STATE_CLAMP : new_rx5;
                    rx6 <= (new_rx6 >  STATE_CLAMP) ?  STATE_CLAMP :
                           (new_rx6 < -STATE_CLAMP) ? -STATE_CLAMP : new_rx6;
                    rx7 <= (new_rx7 >  STATE_CLAMP) ?  STATE_CLAMP :
                           (new_rx7 < -STATE_CLAMP) ? -STATE_CLAMP : new_rx7;
                    rx8 <= (new_rx8 >  STATE_CLAMP) ?  STATE_CLAMP :
                           (new_rx8 < -STATE_CLAMP) ? -STATE_CLAMP : new_rx8;
                    valid_reg <= 1'b1;
                    state <= S_K1;
                end

                default: state <= S_K1;
            endcase
        end
    end

    assign x1 = rx1; assign x2 = rx2; assign x3 = rx3; assign x4 = rx4;
    assign x5 = rx5; assign x6 = rx6; assign x7 = rx7; assign x8 = rx8;
    assign valid = valid_reg;

endmodule
