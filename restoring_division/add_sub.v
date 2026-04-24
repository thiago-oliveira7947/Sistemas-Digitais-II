module add_sub #(
    parameter N = 8
)(
    input wire [N-1:0] a,
    input wire [N-1:0] b,
    input wire sub, // 0: soma (A+B), 1: subtração (A-B)
    output wire [N-1:0] result,
    output wire cout, // carry out
    output wire overflow, // overflow em complemento de 2
    output wire negative // result[N-1]: resultado negativo
);

wire [N-1:0] b_xor;
assign b_xor = b ^ {N{sub}};

wire [N:0] sum_full;
assign sum_full = {1'b0, a} + {1'b0, b_xor} + {{N{1'b0}}, sub};

assign result = sum_full[N-1:0];
assign cout = sum_full[N];

assign overflow = (a[N-1] & b_xor[N-1] & ~result[N-1]) |
                  (~a[N-1] & ~b_xor[N-1] & result[N-1]);

assign negative = result[N-1];

endmodule
