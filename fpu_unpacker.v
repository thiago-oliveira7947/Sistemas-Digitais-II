module fpu_unpacker (
    input  wire [31:0] operand,
    output wire        sign,
    output wire [7:0]  exp,
    output wire [23:0] mant,
    output wire        is_zero,
    output wire        is_inf,
    output wire        is_nan,
    output wire        is_subnormal
);

    wire [22:0] frac;

    // padrao ieee
    assign sign = operand[31];
    assign exp  = operand[30:23];
    assign frac = operand[22:0];

    // casos especiais
    // expoente todo em 0
    assign is_zero      = (exp == 8'h00) && (frac == 23'h000000);
    assign is_subnormal = (exp == 8'h00) && (frac != 23'h000000);
    
    // expoente todo em 1 (255 em decimal / FF em hexa)
    assign is_inf       = (exp == 8'hFF) && (frac == 23'h000000);
    assign is_nan       = (exp == 8'hFF) && (frac != 23'h000000);

    // reconstrucao da mantissa
    // se o expoente for 0 (zero ou subnormal), o bit a esquerda eh 0.
    // para todos os numeros normais, o bit a esquerda eh 1.
    assign mant = (exp == 8'h00) ? {1'b0, frac} : {1'b1, frac};

endmodule