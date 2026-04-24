module fpu (
    input  wire        clock,
    input  wire        reset,
    input  wire        start,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  op, // 000:ADD, 001:SUB, 010:MUL, 011:DIV, 100:EQ, 101:SLT
    
    output wire [31:0] c,
    output wire        busy,
    output wire        done,
    output wire        f_inv_op,
    output wire        f_div_zero,
    output wire        f_overflow,
    output wire        f_underflow,
    output wire        f_inexact
);

    // unpacking dos operandos
    wire sign_a, sign_b;
    wire [7:0] exp_a, exp_b;
    wire [23:0] mant_a, mant_b;
    wire is_zero_a, is_zero_b, is_inf_a, is_inf_b, is_nan_a, is_nan_b, is_subnorm_a, is_subnorm_b;

    fpu_unpacker unp_a (
        .operand(a), .sign(sign_a), .exp(exp_a), .mant(mant_a),
        .is_zero(is_zero_a), .is_inf(is_inf_a), .is_nan(is_nan_a), .is_subnormal(is_subnorm_a)
    );

    fpu_unpacker unp_b (
        .operand(b), .sign(sign_b), .exp(exp_b), .mant(mant_b),
        .is_zero(is_zero_b), .is_inf(is_inf_b), .is_nan(is_nan_b), .is_subnormal(is_subnorm_b)
    );

    // ADD / SUB
    wire add_sign;
    wire [7:0] add_exp;
    wire [27:0] add_mant;
    fpu_add_sub adder (
        .sign_a(sign_a), .exp_a(exp_a), .mant_a(mant_a),
        .sign_b(sign_b), .exp_b(exp_b), .mant_b(mant_b),
        .op_sub(op[0]), // 0 para ADD, 1 para SUB
        .res_sign(add_sign), .res_exp(add_exp), .res_mant(add_mant)
    );

    // MUL
    wire mul_sign;
    wire [9:0] mul_exp;
    wire [27:0] mul_mant;
    wire mul_busy_out, mul_done_out;
    reg  mul_start_reg;

    fpu_mul multiplier (
        .clock(clock), .reset(reset), .start(mul_start_reg),
        .sign_a(sign_a), .exp_a(exp_a), .mant_a(mant_a),
        .sign_b(sign_b), .exp_b(exp_b), .mant_b(mant_b),
        .busy(mul_busy_out), .done(mul_done_out),
        .res_sign(mul_sign), .res_exp(mul_exp), .res_mant(mul_mant)
    );

    // DIV
    wire div_sign, div_f_div_zero;
    wire [9:0] div_exp;
    wire [27:0] div_mant;
    wire div_busy_out, div_done_out;
    reg  div_start_reg;

    fpu_div divider (
        .clock(clock), .reset(reset), .start(div_start_reg),
        .sign_a(sign_a), .exp_a(exp_a), .mant_a(mant_a),
        .sign_b(sign_b), .exp_b(exp_b), .mant_b(mant_b),
        .busy(div_busy_out), .done(div_done_out), .f_div_zero(div_f_div_zero),
        .res_sign(div_sign), .res_exp(div_exp), .res_mant(div_mant)
    );

    // CMP (EQ / SLT)
    wire [31:0] cmp_res;
    fpu_cmp comparator (
        .sign_a(sign_a), .exp_a(exp_a), .mant_a(mant_a), .is_zero_a(is_zero_a),
        .sign_b(sign_b), .exp_b(exp_b), .mant_b(mant_b), .is_zero_b(is_zero_b),
        .is_slt(op[0]), // 0 para EQ, 1 para SLT
        .res_cmp(cmp_res)
    );

    // mux normalizador
    reg        norm_sign_in;
    reg [9:0]  norm_exp_in;
    reg [27:0] norm_mant_in;

    always @(*) begin
        case(op)
            3'b000, 3'b001: begin
                norm_sign_in = add_sign;
                norm_exp_in  = {2'b00, add_exp};
                norm_mant_in = add_mant;
            end
            3'b010: begin
                norm_sign_in = mul_sign;
                norm_exp_in  = mul_exp;
                norm_mant_in = mul_mant;
            end
            3'b011: begin
                norm_sign_in = div_sign;
                norm_exp_in  = div_exp;
                norm_mant_in = div_mant;
            end
            default: begin
                norm_sign_in = 1'b0;
                norm_exp_in  = 10'd0;
                norm_mant_in = 28'd0;
            end
        endcase
    end

    wire        norm_sign_out, norm_overflow, norm_underflow, norm_inexact;
    wire [7:0]  norm_exp_out;
    wire [22:0] norm_frac_out;

    fpu_normalizer normalizer (
        .sign(norm_sign_in), .exp_in(norm_exp_in), .mant_in(norm_mant_in),
        .res_sign(norm_sign_out), .res_exp(norm_exp_out), .res_frac(norm_frac_out),
        .f_overflow(norm_overflow), .f_underflow(norm_underflow), .f_inexact(norm_inexact)
    );

    // operacoes invalidas
    wire is_inv_add = (op == 3'b000) && is_inf_a && is_inf_b && (sign_a != sign_b);
    wire is_inv_sub = (op == 3'b001) && is_inf_a && is_inf_b && (sign_a == sign_b);
    wire is_inv_mul = (op == 3'b010) && ((is_zero_a && is_inf_b) || (is_inf_a && is_zero_b));
    wire is_inv_div = (op == 3'b011) && ((is_zero_a && is_zero_b) || (is_inf_a && is_inf_b));
    wire flag_inv_op_comb = is_nan_a || is_nan_b || is_inv_add || is_inv_sub || is_inv_mul || is_inv_div;

    reg        spec_is_inf;
    reg        spec_is_zero;
    reg        spec_sign;

    always @(*) begin
        spec_is_inf  = 1'b0;
        spec_is_zero = 1'b0;
        spec_sign    = 1'b0;

        case (op)
            3'b000: begin
                if (is_inf_a) begin spec_is_inf = 1'b1; spec_sign = sign_a; end
                if (is_inf_b) begin spec_is_inf = 1'b1; spec_sign = sign_b; end
            end
            3'b001: begin
                if (is_inf_a) begin spec_is_inf = 1'b1; spec_sign = sign_a; end
                if (is_inf_b) begin spec_is_inf = 1'b1; spec_sign = ~sign_b; end
            end
            3'b010: begin
                if (is_inf_a || is_inf_b) begin spec_is_inf = 1'b1; spec_sign = sign_a ^ sign_b; end
            end
            3'b011: begin
                if (is_inf_a && !is_inf_b) begin spec_is_inf = 1'b1; spec_sign = sign_a ^ sign_b; end
                if (!is_inf_a && is_inf_b) begin spec_is_zero = 1'b1; spec_sign = sign_a ^ sign_b; end 
            end
            default: ;
        endcase
    end

    // fsm
    reg [1:0] state;
    localparam IDLE    = 2'd0;
    localparam COMPUTE = 2'd1;
    localparam FINISH  = 2'd2;

    reg [31:0] reg_c;
    reg reg_busy, reg_done;
    reg reg_f_inv_op, reg_f_div_zero, reg_f_overflow, reg_f_underflow, reg_f_inexact;

    assign c           = reg_c;
    assign busy        = reg_busy;
    assign done        = reg_done;
    assign f_inv_op    = reg_f_inv_op;
    assign f_div_zero  = reg_f_div_zero;
    assign f_overflow  = reg_f_overflow;
    assign f_underflow = reg_f_underflow;
    assign f_inexact   = reg_f_inexact;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state           <= IDLE;
            reg_busy        <= 1'b0;
            reg_done        <= 1'b0;
            div_start_reg   <= 1'b0;
            mul_start_reg   <= 1'b0;
            reg_c           <= 32'd0;
            reg_f_inv_op    <= 1'b0;
            reg_f_div_zero  <= 1'b0;
            reg_f_overflow  <= 1'b0;
            reg_f_underflow <= 1'b0;
            reg_f_inexact   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    reg_done <= 1'b0;
                    if (start) begin
                        reg_busy <= 1'b1;
                        if (op == 3'b011) begin
                            div_start_reg <= 1'b1;
                        end else if (op == 3'b010) begin
                            mul_start_reg <= 1'b1;
                        end
                        state <= COMPUTE;
                    end
                end

                COMPUTE: begin
                    div_start_reg <= 1'b0;
                    mul_start_reg <= 1'b0; 
                    
                    if (op == 3'b011) begin
                        if (div_done_out) state <= FINISH;
                    end else if (op == 3'b010) begin
                        if (mul_done_out) state <= FINISH;
                    end else begin
                        state <= FINISH; 
                    end
                end

                FINISH: begin
                    reg_busy <= 1'b0;
                    reg_done <= 1'b1;
                    
                    reg_f_inv_op   <= flag_inv_op_comb;
                    reg_f_div_zero <= (op == 3'b011) ? (is_zero_b && !is_zero_a && !is_inf_a && !is_nan_a) : 1'b0;
                    
                    if (op == 3'b100 || op == 3'b101) begin
                        reg_c           <= cmp_res;
                        reg_f_overflow  <= 1'b0;
                        reg_f_underflow <= 1'b0;
                        reg_f_inexact   <= 1'b0;
                    end else if (flag_inv_op_comb) begin
                        reg_c           <= 32'h7FC00000;
                        reg_f_overflow  <= 1'b0;
                        reg_f_underflow <= 1'b0;
                        reg_f_inexact   <= 1'b0;
                    end else if (op == 3'b011 && is_zero_b) begin
                        reg_c           <= {sign_a ^ sign_b, 8'hFF, 23'd0};
                        reg_f_overflow  <= 1'b0;
                        reg_f_underflow <= 1'b0;
                        reg_f_inexact   <= 1'b0;
                    end else if (spec_is_inf) begin
                        reg_c           <= {spec_sign, 8'hFF, 23'd0};
                        reg_f_overflow  <= 1'b0; 
                        reg_f_underflow <= 1'b0;
                        reg_f_inexact   <= 1'b0;
                    end else if (spec_is_zero) begin
                        reg_c           <= {spec_sign, 31'd0};
                        reg_f_overflow  <= 1'b0;
                        reg_f_underflow <= 1'b0;
                        reg_f_inexact   <= 1'b0;
                    end else begin
                        reg_c           <= {norm_sign_out, norm_exp_out, norm_frac_out};
                        reg_f_overflow  <= norm_overflow;
                        reg_f_underflow <= norm_underflow;
                        reg_f_inexact   <= norm_inexact;
                    end
                    
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule

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
    
    // CORREÇÃO: Garante que o sticky capture bits mesmo se o exp_diff for maior que o shifter suporta
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

module fpu_mul (
    input  wire        clock,
    input  wire        reset,
    input  wire        start,
    
    // Operando A desempacotado
    input  wire        sign_a,
    input  wire [7:0]  exp_a,
    input  wire [23:0] mant_a,
    
    // Operando B desempacotado
    input  wire        sign_b,
    input  wire [7:0]  exp_b,
    input  wire [23:0] mant_b,
    
    // Sinais de controle da FSM
    output reg         busy,
    output reg         done,
    
    // Resultados brutos (antes da normalização)
    output wire        res_sign,
    output wire [9:0]  res_exp,
    output wire [27:0] res_mant 
);

    // -------------------------------------------------------------------------
    // 1. Sinal e Expoente (Lógica Combinacional Isolada)
    // -------------------------------------------------------------------------
    // A soma e subtração isoladas aqui são permitidas pelo spec do EP
    assign res_sign = sign_a ^ sign_b;
    
    wire [9:0] exp_a_ext = {2'b00, exp_a};
    wire [9:0] exp_b_ext = {2'b00, exp_b};
    assign res_exp = exp_a_ext + exp_b_ext - 10'd127;

    // -------------------------------------------------------------------------
    // 2. Multiplicação das Mantissas (Shift-and-Add Sequencial)
    // -------------------------------------------------------------------------
    reg [47:0] acc;           // Acumulador do produto parcial
    reg [47:0] multiplicand;  // Mantissa A estendida para deslocamento
    reg [23:0] multiplier;    // Mantissa B (consumida bit a bit)
    reg [4:0]  count;
    
    reg [1:0]  state;
    localparam IDLE    = 2'd0;
    localparam COMPUTE = 2'd1;
    localparam FINISH  = 2'd2;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state        <= IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            acc          <= 48'd0;
            multiplicand <= 48'd0;
            multiplier   <= 24'd0;
            count        <= 5'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        busy         <= 1'b1;
                        acc          <= 48'd0;
                        multiplicand <= {24'd0, mant_a}; // Carrega A na parte baixa
                        multiplier   <= mant_b;          // Carrega B
                        count        <= 5'd24;           // 24 bits a processar
                        state        <= COMPUTE;
                    end
                end
                
                COMPUTE: begin
                    if (count > 0) begin
                        // Se o bit da ponta do multiplicador for 1, soma no acumulador
                        if (multiplier[0] == 1'b1) begin
                            acc <= acc + multiplicand;
                        end
                        // Desloca o multiplicando para a esquerda (aumenta o peso)
                        multiplicand <= multiplicand << 1;
                        // Desloca o multiplicador para a direita (descarta o bit lido)
                        multiplier   <= multiplier >> 1;
                        
                        count <= count - 1;
                    end else begin
                        state <= FINISH;
                    end
                end
                
                FINISH: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 3. Compatibilização do formato GRS (Guard, Round, Sticky)
    // -------------------------------------------------------------------------
    wire guard_bit  = acc[22];
    wire round_bit  = acc[21];
    wire sticky_bit = |acc[20:0]; // OR de todos os bits descartados abaixo de Round

    assign res_mant = {acc[47:23], guard_bit, round_bit, sticky_bit};

endmodule

module fpu_div (
    input  wire        clock,
    input  wire        reset,
    input  wire        start,
    input  wire        sign_a,
    input  wire [7:0]  exp_a,
    input  wire [23:0] mant_a,
    input  wire        sign_b,
    input  wire [7:0]  exp_b,
    input  wire [23:0] mant_b,
    output reg         busy,
    output reg         done,
    output wire        f_div_zero,
    output wire        res_sign,
    output wire [9:0]  res_exp,
    output wire [27:0] res_mant 
);
    assign res_sign   = sign_a ^ sign_b;
    assign f_div_zero = (mant_b == 24'd0) && (exp_b == 8'd0);

    wire [9:0] exp_a_ext = {2'b00, exp_a};
    wire [9:0] exp_b_ext = {2'b00, exp_b};
    assign res_exp = exp_a_ext - exp_b_ext + 10'd127;

    reg [24:0] acc;
    reg [25:0] quociente;
    reg [24:0] divisor_reg;
    reg [4:0]  count;
    reg        sticky_bit_reg;
    
    reg [2:0]  state;
    localparam IDLE     = 3'd0;
    localparam SUBTRACT = 3'd1;
    localparam RESTORE  = 3'd2;
    localparam SHIFT    = 3'd3;
    localparam CLEANUP  = 3'd4;
    localparam FIM      = 3'd5;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state          <= IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;
            count          <= 5'd0;
            acc            <= 25'd0;
            quociente      <= 26'd0;
            divisor_reg    <= 25'd0;
            sticky_bit_reg <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start && !f_div_zero) begin
                        busy           <= 1'b1;
                        acc            <= {1'b0, mant_a}; 
                        quociente      <= 26'd0;
                        divisor_reg    <= {1'b0, mant_b};
                        count          <= 5'd26;
                        sticky_bit_reg <= 1'b0;
                        state          <= SUBTRACT;
                    end else if (start && f_div_zero) begin
                        done <= 1'b1;
                    end
                end

                SUBTRACT: begin
                    acc   <= acc - divisor_reg;
                    state <= RESTORE;
                end

                RESTORE: begin
                    if (acc[24] == 1'b1) begin
                        acc       <= acc + divisor_reg;
                        quociente <= {quociente[24:0], 1'b0};
                    end else begin
                        quociente <= {quociente[24:0], 1'b1};
                    end

                    // O 'end' que estava aqui em cima foi removido.
                    if (count == 5'd1) begin
                        state <= CLEANUP; 
                    end else begin
                        count <= count - 1;
                        state <= SHIFT;
                    end
                end // <- O 'end' correto do RESTORE é aqui.

                SHIFT: begin
                    acc   <= {acc[23:0], 1'b0};
                    state <= SUBTRACT;
                end

                CLEANUP: begin
                    sticky_bit_reg <= (acc != 25'd0);
                    state <= FIM;
                end

                FIM: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    assign res_mant = {2'b00, quociente[25:2], quociente[1], quociente[0], sticky_bit_reg};

endmodule

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

module fpu_normalizer (
    input  wire        sign,
    input  wire [9:0]  exp_in,    // 10 bits (recebe do ADD/SUB ou MUL/DIV)
    input  wire [27:0] mant_in,   // Formato: [27:26] Int, [25:3] Frac, [2] G, [1] R, [0] S
    
    output reg         res_sign,
    output reg  [7:0]  res_exp,
    output reg  [22:0] res_frac,
    output reg         f_overflow,
    output reg         f_underflow,
    output reg         f_inexact
);

    // --- Fios de conexão com os Shifters de Normalização ---
    wire [27:0] mant_left_out;
    wire [27:0] mant_right_out;
    reg  [4:0]  left_shift_amt;
    
    // 1. Codificador de Prioridade (Bit 27 e 26 mapeados corretamente)
    always @(*) begin
        if      (mant_in[27] || mant_in[26]) left_shift_amt = 5'd0;
        else if (mant_in[25]) left_shift_amt = 5'd1;
        else if (mant_in[24]) left_shift_amt = 5'd2;
        else if (mant_in[23]) left_shift_amt = 5'd3;
        else if (mant_in[22]) left_shift_amt = 5'd4;
        else if (mant_in[21]) left_shift_amt = 5'd5;
        else if (mant_in[20]) left_shift_amt = 5'd6;
        else if (mant_in[19]) left_shift_amt = 5'd7;
        else if (mant_in[18]) left_shift_amt = 5'd8;
        else if (mant_in[17]) left_shift_amt = 5'd9;
        else if (mant_in[16]) left_shift_amt = 5'd10;
        else if (mant_in[15]) left_shift_amt = 5'd11;
        else if (mant_in[14]) left_shift_amt = 5'd12;
        else if (mant_in[13]) left_shift_amt = 5'd13;
        else if (mant_in[12]) left_shift_amt = 5'd14;
        else if (mant_in[11]) left_shift_amt = 5'd15;
        else if (mant_in[10]) left_shift_amt = 5'd16;
        else if (mant_in[9])  left_shift_amt = 5'd17;
        else if (mant_in[8])  left_shift_amt = 5'd18;
        else if (mant_in[7])  left_shift_amt = 5'd19;
        else if (mant_in[6])  left_shift_amt = 5'd20;
        else if (mant_in[5])  left_shift_amt = 5'd21;
        else if (mant_in[4])  left_shift_amt = 5'd22;
        else if (mant_in[3])  left_shift_amt = 5'd23;
        else if (mant_in[2])  left_shift_amt = 5'd24;
        else if (mant_in[1])  left_shift_amt = 5'd25;
        else if (mant_in[0])  left_shift_amt = 5'd26;
        else                  left_shift_amt = 5'd0;
    end

    // 2. Instanciação dos Barrel Shifters Base
    barrel_shifter_right_28 shift_r (
        .data_in(mant_in),
        .shamt(5'd1),
        .data_out(mant_right_out)
    );

    barrel_shifter_left_28 shift_l (
        .data_in(mant_in),
        .shamt(left_shift_amt),
        .data_out(mant_left_out)
    );

    // --- Variáveis Internas do Estágio de Arredondamento ---
    reg [27:0] shifted_mant;
    reg signed [11:0] adj_exp;       
    reg signed [11:0] signed_exp_in; 
    
    reg        guard, round, sticky;
    reg        round_up;
    reg [24:0] rounded_mant;   
    reg        inexact_temp;

    // 3. BLOCO 1: Ajuste de Expoente e Arredondamento
    always @(*) begin
        signed_exp_in = { {2{exp_in[9]}}, exp_in }; // Extensão com sinal

        if (mant_in == 28'd0) begin
            shifted_mant = 28'd0; 
            adj_exp      = 12'd0;
        end else begin
            if (mant_in[27] == 1'b1) begin
                shifted_mant = mant_right_out;
                shifted_mant[0] = mant_right_out[0] | mant_in[0]; 
                adj_exp = signed_exp_in + 12'd1;
            end else if (mant_in[26] == 1'b1) begin
                shifted_mant = mant_in;
                adj_exp = signed_exp_in;
            end else begin
                shifted_mant = mant_left_out;
                adj_exp = signed_exp_in - $signed({7'd0, left_shift_amt}); 
            end
        end

        guard  = shifted_mant[2];
        round  = shifted_mant[1];
        sticky = shifted_mant[0];
        
        inexact_temp = guard | round | sticky;
        round_up     = guard & (round | sticky | shifted_mant[3]);
        rounded_mant = {1'b0, shifted_mant[26:3]} + round_up;

        // Se o arredondamento transbordar o bit implícito, normaliza de novo
        if (rounded_mant[24] == 1'b1) begin
            rounded_mant = {1'b0, rounded_mant[24:1]};
            adj_exp      = adj_exp + 12'd1;
        end
    end

    // =========================================================================
    // 4. INSTANCIAÇÃO ESTRUTURAL DO UNDERFLOW (Fora do Always Block)
    // =========================================================================
    
    wire signed [11:0] underflow_diff = 12'sd1 - adj_exp;
    
    // Evita deslocar números não-subnormais ou estourar o limite de 24 do shifter
    wire [4:0] subnormal_shamt = (underflow_diff > 12'sd24) ? 5'd24 : 
                                 (underflow_diff > 12'sd0)  ? underflow_diff[4:0] : 5'd0;

    wire [27:0] subnormal_shifted_out;

    // Instancia o Barrel Shifter para executar o "Gradual Underflow" fisicamente
    barrel_shifter_right_28 uflow_shifter (
        // Mandamos o bit implícito (bit 23) e a fração alinhados à direita do bus
        .data_in({4'b0, rounded_mant[23:0]}),
        .shamt(subnormal_shamt),
        .data_out(subnormal_shifted_out)
    );

    // =========================================================================

    // 5. BLOCO 2: Decisão Final das Saídas e Flags
    always @(*) begin
        res_sign    = sign;
        f_overflow  = 1'b0;
        f_underflow = 1'b0;
        f_inexact   = inexact_temp;
        res_exp     = 8'd0;
        res_frac    = 23'd0;

        if (mant_in == 28'd0) begin
            res_exp  = 8'd0;
            res_frac = 23'd0;
        end else if ($signed(adj_exp) >= 255) begin
            // Overflow: Retorna Infinito
            f_overflow = 1'b1;
            res_exp    = 8'hFF;
            res_frac   = 23'd0;
        end else if ($signed(adj_exp) <= 0) begin
            // Underflow: Pega o resultado diretamente do barrel_shifter de hardware
            f_underflow = 1'b1;
            res_exp     = 8'd0;
            res_frac    = subnormal_shifted_out[22:0];
        end else begin
            // Normal
            res_exp  = adj_exp[7:0];
            res_frac = rounded_mant[22:0];
        end
    end

endmodule

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

module barrel_shifter_left_28 (
    input  wire [27:0] data_in,
    input  wire [4:0]  shamt,
    output wire [27:0] data_out
);
    wire [27:0] s0, s1, s2, s3, s4;

    assign s0 = shamt[0] ? {data_in[26:0], 1'b0} : data_in;
    assign s1 = shamt[1] ? {s0[25:0], 2'b0}      : s0;
    assign s2 = shamt[2] ? {s1[23:0], 4'b0}      : s1;
    assign s3 = shamt[3] ? {s2[19:0], 8'b0}      : s2;
    assign s4 = shamt[4] ? {s3[11:0], 16'b0}     : s3;

    assign data_out = s4;
endmodule

// Módulo de deslocamento para a direita de 28 bits (Puramente Combinacional)
module barrel_shifter_right_28 (
    input  wire [27:0] data_in,
    input  wire [4:0]  shamt,   // Quantidade de deslocamento (0 a 31)
    output wire [27:0] data_out
);
    wire [27:0] s0, s1, s2, s3, s4;

    assign s0 = shamt[0] ? {1'b0, data_in[27:1]} : data_in;
    assign s1 = shamt[1] ? {2'b0, s0[27:2]}      : s0;
    assign s2 = shamt[2] ? {4'b0, s1[27:4]}      : s1;
    assign s3 = shamt[3] ? {8'b0, s2[27:8]}      : s2;
    assign s4 = shamt[4] ? {16'b0, s3[27:16]}    : s3;

    assign data_out = s4;
endmodule

module barrel_shifter_right_51 (
    input  wire [50:0] data_in,
    input  wire [4:0]  shamt,   // Quantidade de deslocamento (0 a 31)
    output wire [50:0] data_out
);
    wire [50:0] s0, s1, s2, s3, s4;

    // Estágio 0: Desloca 1 bit se shamt[0] for 1
    assign s0 = shamt[0] ? {1'b0, data_in[50:1]} : data_in;

    // Estágio 1: Desloca 2 bits se shamt[1] for 1
    assign s1 = shamt[1] ? {2'b0, s0[50:2]} : s0;

    // Estágio 2: Desloca 4 bits se shamt[2] for 1
    assign s2 = shamt[2] ? {4'b0, s1[50:4]} : s1;

    // Estágio 3: Desloca 8 bits se shamt[3] for 1
    assign s3 = shamt[3] ? {8'b0, s2[50:8]} : s2;

    // Estágio 4: Desloca 16 bits se shamt[4] for 1
    assign s4 = shamt[4] ? {16'b0, s3[50:16]} : s3;

    assign data_out = s4;
endmodule

