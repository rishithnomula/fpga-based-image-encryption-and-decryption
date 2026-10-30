
//   dx1 = beta1*(x2 - x1) + x4
//   dx2 = -beta2*x1 - x1*x3 + x4
//   dx3 = -x1*x2 - x3 - x4 + x7      
//   dx4 = -beta3*(x1 + x2) + x5
//   dx5 = -x2 - beta4*x4 + x6
//   dx6 = -beta5*(x1 + x5) + beta4*x7
//   dx7 = -beta6*(x1 + x6 - x8)
//   dx8 = -beta7*x7
// =============================================================
module derivative_function (
    input  wire signed [31:0] x1,
    input  wire signed [31:0] x2,
    input  wire signed [31:0] x3,
    input  wire signed [31:0] x4,
    input  wire signed [31:0] x5,
    input  wire signed [31:0] x6,
    input  wire signed [31:0] x7,
    input  wire signed [31:0] x8,
    output wire signed [31:0] dx1,
    output wire signed [31:0] dx2,
    output wire signed [31:0] dx3,
    output wire signed [31:0] dx4,
    output wire signed [31:0] dx5,
    output wire signed [31:0] dx6,
    output wire signed [31:0] dx7,
    output wire signed [31:0] dx8
);

    // Fixed constants in Q16.16 (value * 65536, rounded)
    localparam signed [31:0] BETA1 = 32'sd655360;  // 10.0
    localparam signed [31:0] BETA2 = 32'sd4980736; // 76.0
    localparam signed [31:0] BETA3 = 32'sd196608;  // 3.0
    localparam signed [31:0] BETA4 = 32'sd13107;   // 0.2
    localparam signed [31:0] BETA5 = 32'sd6554;    // 0.1
    localparam signed [31:0] BETA6 = 32'sd6554;    // 0.1
    localparam signed [31:0] BETA7 = 32'sd13107;   // 0.2

    wire signed [31:0] m_x1x3, m_x1x2;
    wire signed [31:0] m_beta1_diff, m_beta2_x1, m_beta3_sum;
    wire signed [31:0] m_beta4_x4,   m_beta5_sum, m_beta4_x7;
    wire signed [31:0] m_beta6_term, m_beta7_x7;

    fixed_mult u_m_x1x3   (.a(x1),.b(x3),.result(m_x1x3));
    fixed_mult u_m_x1x2   (.a(x1),.b(x2),.result(m_x1x2));
    fixed_mult u_m_b1diff (.a(BETA1), .b(x2 - x1),.result(m_beta1_diff));
    fixed_mult u_m_b2x1   (.a(BETA2), .b(x1),.result(m_beta2_x1));
    fixed_mult u_m_b3sum  (.a(BETA3), .b(x1 + x2),.result(m_beta3_sum));
    fixed_mult u_m_b4x4   (.a(BETA4), .b(x4),.result(m_beta4_x4));
    fixed_mult u_m_b5sum  (.a(BETA5), .b(x1 + x5),.result(m_beta5_sum));
    fixed_mult u_m_b4x7   (.a(BETA4), .b(x7),.result(m_beta4_x7));
    fixed_mult u_m_b6term (.a(BETA6), .b(x1 + x6 - x8),.result(m_beta6_term));
    fixed_mult u_m_b7x7   (.a(BETA7), .b(x7),.result(m_beta7_x7));

    assign dx1 =  m_beta1_diff + x4;
    assign dx2 = -m_beta2_x1 - m_x1x3 + x4;
    assign dx3 = -m_x1x2 - x3 - x4 + x7; 
    assign dx4 = -m_beta3_sum + x5;
    assign dx5 = -x2 - m_beta4_x4 + x6;
    assign dx6 = -m_beta5_sum + m_beta4_x7;
    assign dx7 = -m_beta6_term;
    assign dx8 = -m_beta7_x7;

endmodule
