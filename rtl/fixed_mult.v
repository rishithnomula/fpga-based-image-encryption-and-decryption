
module fixed_mult (
    input  wire signed [31:0] a,
    input  wire signed [31:0] b,
    output wire signed [31:0] result
);

    wire signed [63:0] full_product;
    wire signed [63:0] rounded_product;

    assign full_product    = a * b;                    
    assign rounded_product = full_product + 64'sd32768; 
    assign result          = rounded_product[47:16];   

endmodule
