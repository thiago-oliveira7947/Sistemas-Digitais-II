module fpu_add_sub (
    input  wire        sign_a,
    input  wire [7:0]  exp_a,
    input  wire [23:0] mant_a,
    input  wire        sign_b,
    input  wire [7:0]  exp_b,
    input  wire [23:0] mant_b,
    input  wire        op_sub,
    output wire        res_sign,
    output wire [7:0]  res_exp,
    output wire [27:0] res_mant // 28 bits: [27:26] Inteiro (pode gerar carry), [25:3] Fração, [2] Guard, [1] Round, [0] Sticky 
);

    // Se os sinais forem iguais e ADD, ou sinais diferentes e SUB -> Soma Efetiva (0)
    // Caso contrário -> Subtração Efetiva (1)
    wire eff_sub = sign_a ^ (sign_b ^ op_sub);

    // Descobrir qual é o maior operando em magnitude
    wire a_is_larger = (exp_a > exp_b) || ((exp_a == exp_b) && (mant_a > mant_b));
    
    wire [7:0]  larger_exp   = a_is_larger ? exp_a  : exp_b;
    wire [23:0] larger_mant  = a_is_larger ? mant_a : mant_b;
    wire [7:0]  smaller_exp  = a_is_larger ? exp_b  : exp_a;
    wire [23:0] smaller_mant = a_is_larger ? mant_b : mant_a;

    // Calculo para alinhar os expoentes
    wire [7:0] exp_diff = larger_exp - smaller_exp;
    
    // Se a diferença for maior que 26, todos os bits do menor número caem no bit Sticky.
    wire [7:0] shift_amt = (exp_diff > 8'd26) ? 8'd27 : exp_diff;

    wire [50:0] mant_to_shift = {1'b0, smaller_mant, 26'b0};
    wire [50:0] shifted_smaller;

    barrel_shifter_right_51 shifter_inst (
        .data_in(mant_to_shift),
        .shamt(shift_amt[4:0]),  // Pegamos apenas os 5 bits necessários (máx 31)
        .data_out(shifted_smaller)
    );
    // ----------------------------------------------------
        
    // Alinhamento com preservacao dos bits Guard, Round e Sticky (GRS)
    wire [23:0] aligned_smaller_mant = shifted_smaller[49:26];
    wire        guard_bit            = shifted_smaller[25];
    wire        round_bit            = shifted_smaller[24];
    
    //Garante que o sticky capture bits mesmo se o exp_diff for maior que o shifter suporta
    wire        force_sticky         = (exp_diff > 8'd26) & (|smaller_mant);
    wire        sticky_bit           = (|shifted_smaller[23:0]) | force_sticky;

    // Concatenando
    wire [27:0] larger_mant_ext  = {2'b00, larger_mant, 3'b000};
    wire [27:0] smaller_mant_ext = {2'b00, aligned_smaller_mant, guard_bit, round_bit, sticky_bit};
    // Executar a adicao ou subtracao
    wire [27:0] calc_mant = eff_sub ? (larger_mant_ext - smaller_mant_ext) 
                                    : (larger_mant_ext + smaller_mant_ext);

    // O sinal final é o sinal do maior número, exceto se for SUB efetiva e A == B (Zero positivo)
    assign res_sign = (eff_sub && (larger_mant == smaller_mant) && (exp_a == exp_b)) ? 1'b0 
                               : (a_is_larger ? sign_a : (sign_b ^ op_sub));
                               
    assign res_exp  = larger_exp;
    assign res_mant = calc_mant;  // Mantissa nao normalizada

endmodule