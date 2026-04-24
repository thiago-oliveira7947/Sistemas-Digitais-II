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
    wire [7:0]  raw_exp = operand[30:23];
    wire [22:0] frac    = operand[22:0];

    assign sign = operand[31];

    assign is_zero      = (raw_exp == 8'h00) && (frac == 23'h000000);
    assign is_subnormal = (raw_exp == 8'h00) && (frac != 23'h000000);
    assign is_inf       = (raw_exp == 8'hFF) && (frac == 23'h000000);
    assign is_nan       = (raw_exp == 8'hFF) && (frac != 23'h000000);

    // CORREÇÃO: Subnormais e Zeros compartilham o expoente -126 (unbiased) na FPU interna.
    assign exp  = (raw_exp == 8'h00) ? 8'h01 : raw_exp;
    assign mant = (raw_exp == 8'h00) ? {1'b0, frac} : {1'b1, frac};

endmodule