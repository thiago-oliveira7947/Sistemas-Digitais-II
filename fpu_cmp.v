module fpu_cmp (
    input  wire        sign_a,
    input  wire [7:0]  exp_a,
    input  wire [23:0] mant_a,
    input  wire        is_zero_a,

    input  wire        sign_b,
    input  wire [7:0]  exp_b,
    input  wire [23:0] mant_b,
    input  wire        is_zero_b,

    input  wire        is_slt, 
    output wire [31:0] res_cmp
);

    // deteccao DE NaN
    wire a_is_nan = (exp_a == 8'hFF) && (mant_a[22:0] != 0);
    wire b_is_nan = (exp_b == 8'hFF) && (mant_b[22:0] != 0);
    wire any_nan  = a_is_nan | b_is_nan;

    // igualdade
    wire both_zero = is_zero_a & is_zero_b;

    wire raw_equal = both_zero | 
                     ((sign_a == sign_b) & 
                      (exp_a == exp_b) & 
                      (mant_a == mant_b));

    wire is_equal = any_nan ? 1'b0 : raw_equal;

    // menor que
    wire diff_signs_lt = (sign_a & ~sign_b) & ~both_zero;

    wire mag_a_lt_mag_b = (exp_a < exp_b) | ((exp_a == exp_b) & (mant_a < mant_b));
    wire mag_a_gt_mag_b = (exp_a > exp_b) | ((exp_a == exp_b) & (mant_a > mant_b));

    wire both_pos_lt = (~sign_a & ~sign_b) & mag_a_lt_mag_b;
    wire both_neg_lt = (sign_a & sign_b) & mag_a_gt_mag_b;

    wire raw_lt = diff_signs_lt | both_pos_lt | both_neg_lt;

    wire a_lt_b = any_nan ? 1'b0 : raw_lt;

    // resultado
    wire condition_met = is_slt ? a_lt_b : is_equal;

    // saida
    assign res_cmp = condition_met ? 32'h3F800000 : 32'h00000000;

endmodule