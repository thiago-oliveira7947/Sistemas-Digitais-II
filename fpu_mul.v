module fpu_mul (
    // Operando A desempacotado
    input  wire        sign_a,
    input  wire [7:0]  exp_a,
    input  wire [23:0] mant_a,
    
    // Operando B desempacotado
    input  wire        sign_b,
    input  wire [7:0]  exp_b,
    input  wire [23:0] mant_b,
    
    // Resultados brutos (antes da normalização)
    output wire        res_sign,
    output wire [9:0]  res_exp,  // 10 bits para suportar overflow/underflow intermediário
    output wire [27:0] res_mant  // Formato Padrão: [27:26] Int, [25:3] Frac, [2] G, [1] R, [0] S
);

    // 1. Cálculo do Sinal
    // Na multiplicação, sinais iguais = positivo (0), sinais diferentes = negativo (1)
    assign res_sign = sign_a ^ sign_b;

    // 2. Multiplicação das Mantissas
    // (24 bits * 24 bits = 48 bits de resultado)
    wire [47:0] mult_result = mant_a * mant_b;

    // 3. Compatibilização do formato GRS (Guard, Round, Sticky)
    // A vírgula decimal na multiplicação 24x24 fica entre o bit 46 e 45.
    // mult_result[47:46] -> 2 bits inteiros (ex: 1.1 * 1.1 pode gerar até um 11.xx)
    // mult_result[45:23] -> 23 bits de fração
    // mult_result[22]    -> Bit de Guard
    // mult_result[21]    -> Bit de Round
    // mult_result[20:0]  -> Reduzido por OR para formar o bit Sticky
    wire guard_bit  = mult_result[22];
    wire round_bit  = mult_result[21];
    wire sticky_bit = |mult_result[20:0]; // Se qualquer bit descartado for 1, o sticky é 1

    assign res_mant = {mult_result[47:23], guard_bit, round_bit, sticky_bit};

    // 4. Cálculo do Expoente
    // Pela regra de expoentes (em excesso 127): exp_res = exp_a + exp_b - 127.
    // Usamos extensões para 10 bits para evitar que um underflow (resultado negativo)
    // quebre a lógica antes de chegar no normalizador.
    wire [9:0] exp_a_ext = {2'b00, exp_a};
    wire [9:0] exp_b_ext = {2'b00, exp_b};
    
    assign res_exp = exp_a_ext + exp_b_ext - 10'd127;

endmodule