module fpu (
    input clock, reset, start,
    input [31:0] a, b,
    input [2:0] op, // ADD, SUB, MUL, DIV, EQ, SLT
    output [31:0] c,
    output busy, done,
    output f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact
);

    wire sinal_a, sinal_b;
    wire [7:0] expoente_a, expoente_b;
    wire [23:0] mantissa_a, mantissa_b;
    wire a_eh_zero, b_eh_zero;
    wire a_eh_infinito, b_eh_infinito;
    wire a_eh_nan, b_eh_nan;
    wire a_eh_subnormal, b_eh_subnormal;

    fpu_unpacker campos_a (
        .operando(a), .sinal(sinal_a), .expoente(expoente_a), .mantissa(mantissa_a),
        .eh_zero(a_eh_zero), .eh_infinito(a_eh_infinito), .eh_nan(a_eh_nan), .eh_subnormal(a_eh_subnormal)
    );

    fpu_unpacker campos_b (
        .operando(b), .sinal(sinal_b), .expoente(expoente_b), .mantissa(mantissa_b),
        .eh_zero(b_eh_zero), .eh_infinito(b_eh_infinito), .eh_nan(b_eh_nan), .eh_subnormal(b_eh_subnormal)
    );

    wire sinal_soma;
    wire [7:0] expoente_soma;
    wire [27:0] mantissa_soma;
    fpu_add_sub unidade_soma (
        .sinal_a(sinal_a), .expoente_a(expoente_a), .mantissa_a(mantissa_a),
        .sinal_b(sinal_b), .expoente_b(expoente_b), .mantissa_b(mantissa_b),
        .subtrair(op[0]),
        .sinal_resultado(sinal_soma), .expoente_resultado(expoente_soma), .mantissa_resultado(mantissa_soma)
    );

    wire sinal_mult;
    wire [9:0] expoente_mult;
    wire [27:0] mantissa_mult;
    wire mult_busy, mult_done;
    reg start_mult;

    fpu_mul unidade_mult (
        .clock(clock), .reset(reset), .start(start_mult),
        .sinal_a(sinal_a), .expoente_a(expoente_a), .mantissa_a(mantissa_a),
        .sinal_b(sinal_b), .expoente_b(expoente_b), .mantissa_b(mantissa_b),
        .busy(mult_busy), .done(mult_done),
        .sinal_resultado(sinal_mult), .expoente_resultado(expoente_mult), .mantissa_resultado(mantissa_mult)
    );

    wire sinal_div, div_zero_calc;
    wire [9:0] expoente_div;
    wire [27:0] mantissa_div;
    wire div_busy, div_done;
    reg start_div;

    fpu_div unidade_div (
        .clock(clock), .reset(reset), .start(start_div),
        .sinal_a(sinal_a), .expoente_a(expoente_a), .mantissa_a(mantissa_a),
        .sinal_b(sinal_b), .expoente_b(expoente_b), .mantissa_b(mantissa_b),
        .busy(div_busy), .done(div_done), .f_div_zero(div_zero_calc),
        .sinal_resultado(sinal_div), .expoente_resultado(expoente_div), .mantissa_resultado(mantissa_div)
    );

    wire [31:0] res_comparacao;
    fpu_cmp comparador (
        .sinal_a(sinal_a), .expoente_a(expoente_a), .mantissa_a(mantissa_a), .a_eh_zero(a_eh_zero),
        .sinal_b(sinal_b), .expoente_b(expoente_b), .mantissa_b(mantissa_b), .b_eh_zero(b_eh_zero),
        .faz_menor_que(op[0]),
        .resultado_comp(res_comparacao)
    );


    // mux que escolhe qual resultado vai pro normalizador
    reg sinal_norm_in;
    reg [9:0] expoente_norm_in;
    reg [27:0] mantissa_norm_in;

    always @(*) begin
        case(op)
            3'b000, 3'b001: begin
                sinal_norm_in = sinal_soma;
                expoente_norm_in = {2'b00, expoente_soma};
                mantissa_norm_in = mantissa_soma;
            end
            3'b010: begin
                sinal_norm_in = sinal_mult;
                expoente_norm_in = expoente_mult;
                mantissa_norm_in = mantissa_mult;
            end
            3'b011: begin
                sinal_norm_in = sinal_div;
                expoente_norm_in = expoente_div;
                mantissa_norm_in = mantissa_div;
            end
            default: begin
                sinal_norm_in = 1'b0;
                expoente_norm_in = 10'd0;
                mantissa_norm_in = 28'd0;
            end
        endcase
    end

    wire sinal_norm_out, overflow_norm, underflow_norm, inexato_norm;
    wire [7:0] expoente_norm_out;
    wire [22:0] fracao_norm_out;

    fpu_normalizer normalizador (
        .sinal(sinal_norm_in), .expoente_entrada(expoente_norm_in), .mantissa_entrada(mantissa_norm_in),
        .sinal_resultado(sinal_norm_out), .expoente_resultado(expoente_norm_out), .fracao_resultado(fracao_norm_out),
        .f_overflow(overflow_norm), .f_underflow(underflow_norm), .f_inexact(inexato_norm)
    );

     // deteccao de operacoes invalidas por tipo

    wire a_eh_snan = a_eh_nan && !a[22];
    wire b_eh_snan = b_eh_nan && !b[22];

    wire cmp_invalido = (op == 3'b101) ? (a_eh_nan || b_eh_nan) :
                        (op == 3'b100) ? (a_eh_snan || b_eh_snan) : 1'b0;

    wire inv_soma = (op == 3'b000) && a_eh_infinito && b_eh_infinito && (sinal_a != sinal_b);
    wire inv_sub = (op == 3'b001) && a_eh_infinito && b_eh_infinito && (sinal_a == sinal_b);
    wire inv_mult = (op == 3'b010) && ((a_eh_zero && b_eh_infinito) || (a_eh_infinito && b_eh_zero));
    wire inv_div = (op == 3'b011) && ((a_eh_zero && b_eh_zero) || (a_eh_infinito && b_eh_infinito));
    
    wire inv_op_comb = a_eh_snan || b_eh_snan || inv_soma || inv_sub || inv_mult || inv_div || cmp_invalido;
    wire forca_nan_saida = a_eh_nan || b_eh_nan || inv_op_comb;

    // casos especiais que nao passam pelo normalizador
    reg caso_infinito;
    reg caso_zero;
    reg sinal_especial;

    always @(*) begin
        caso_infinito = 1'b0;
        caso_zero = 1'b0;
        sinal_especial = 1'b0;

        case (op)
            3'b000: begin
                if (a_eh_infinito) begin caso_infinito = 1'b1; sinal_especial = sinal_a; end
                if (b_eh_infinito) begin caso_infinito = 1'b1; sinal_especial = sinal_b; end
            end
            3'b001: begin
                if (a_eh_infinito) begin caso_infinito = 1'b1; sinal_especial = sinal_a; end
                if (b_eh_infinito) begin caso_infinito = 1'b1; sinal_especial = ~sinal_b; end
            end
            3'b010: begin
                if (a_eh_infinito || b_eh_infinito) begin caso_infinito = 1'b1; sinal_especial = sinal_a ^ sinal_b; end
            end
            3'b011: begin
                if (a_eh_infinito && !b_eh_infinito) begin caso_infinito = 1'b1; sinal_especial = sinal_a ^ sinal_b; end
                if (!a_eh_infinito && b_eh_infinito) begin caso_zero = 1'b1; sinal_especial = sinal_a ^ sinal_b; end
            end
            default: ;
        endcase
    end

    reg [1:0] state;
    localparam ESPERA = 2'd0;
    localparam CALCULA = 2'd1;
    localparam CONCLUI = 2'd2;

    reg [31:0] resultado_reg;
    reg busy_reg, done_reg;
    reg flag_inv_op_reg, flag_div_zero_reg, flag_overflow_reg, flag_underflow_reg, flag_inexact_reg;

    assign c = resultado_reg;
    assign busy = busy_reg;
    assign done = done_reg;
    assign f_inv_op = flag_inv_op_reg;
    assign f_div_zero = flag_div_zero_reg;
    assign f_overflow = flag_overflow_reg;
    assign f_underflow = flag_underflow_reg;
    assign f_inexact = flag_inexact_reg;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state <= ESPERA;
            busy_reg <= 1'b0;
            done_reg <= 1'b0;
            start_div <= 1'b0;
            start_mult <= 1'b0;
            resultado_reg <= 32'd0;
            flag_inv_op_reg <= 1'b0;
            flag_div_zero_reg <= 1'b0;
            flag_overflow_reg <= 1'b0;
            flag_underflow_reg <= 1'b0;
            flag_inexact_reg <= 1'b0;
        end else begin
            case (state)
                ESPERA: begin
                    // espera o start. se for mul ou div, dispara o pulso pra unidade sequencial
                    done_reg <= 1'b0;
                    if (start) begin
                        busy_reg <= 1'b1;
                        if (op == 3'b011)
                            start_div <= 1'b1;
                        else if (op == 3'b010)
                            start_mult <= 1'b1;
                        state <= CALCULA;
                    end
                end

                CALCULA: begin
                    // operacoes combinacionais (add/sub/cmp) caem direto em FINISH;
                    // mul e div esperam o done do submodulo
                    start_div <= 1'b0;
                    start_mult <= 1'b0;
                    if (op == 3'b011) begin
                        if (div_done) state <= CONCLUI;
                    end else if (op == 3'b010) begin
                        if (mult_done) state <= CONCLUI;
                    end else begin
                        state <= CONCLUI;
                    end
                end

                CONCLUI: begin
                    // resultado pronto: levanta done, escolhe saida e flags por prioridade
                    busy_reg <= 1'b0;
                    done_reg <= 1'b1;

                    flag_inv_op_reg <= inv_op_comb;
                    flag_div_zero_reg <= (op == 3'b011) ? 
                        (b_eh_zero && !a_eh_zero && !a_eh_infinito && !a_eh_nan && !b_eh_nan) : 1'b0;

                    if (op == 3'b100 || op == 3'b101) begin
                        // comparacao: vem direto do comparador, sem flags aritmeticas
                        resultado_reg <= res_comparacao;
                        flag_overflow_reg <= 1'b0;
                        flag_underflow_reg <= 1'b0;
                        flag_inexact_reg <= 1'b0;
                    end else if (forca_nan_saida) begin
                        // operacao invalida (NaN, Inf-Inf, 0*Inf, 0/0, Inf/Inf): retorna NaN canonico
                        resultado_reg <= 32'h7FC00000;
                        flag_overflow_reg <= 1'b0;
                        flag_underflow_reg <= 1'b0;
                        flag_inexact_reg <= 1'b0;
                    end else if (op == 3'b011 && b_eh_zero) begin
                        // x/0 com x finito nao-nulo: Inf com sinal de a^b e levanta div_zero
                        resultado_reg <= {sinal_a ^ sinal_b, 8'hFF, 23'd0};
                        flag_overflow_reg <= 1'b0;
                        flag_underflow_reg <= 1'b0;
                        flag_inexact_reg <= 1'b0;
                    end else if (caso_infinito) begin
                        // alguma entrada eh Inf e o resultado eh Inf "limpo" (sem overflow real)
                        resultado_reg <= {sinal_especial, 8'hFF, 23'd0};
                        flag_overflow_reg <= 1'b0;
                        flag_underflow_reg <= 1'b0;
                        flag_inexact_reg <= 1'b0;
                    end else if (caso_zero) begin
                        // finito / Inf = 0 com sinal apropriado
                        resultado_reg <= {sinal_especial, 31'd0};
                        flag_overflow_reg <= 1'b0;
                        flag_underflow_reg <= 1'b0;
                        flag_inexact_reg <= 1'b0;
                    end else begin
                        // caminho normal: aritmetica entre finitos passa pelo normalizador
                        resultado_reg <= {sinal_norm_out, expoente_norm_out, fracao_norm_out};
                        flag_overflow_reg <= overflow_norm;
                        flag_underflow_reg <= underflow_norm;
                        flag_inexact_reg <= inexato_norm;
                    end

                    state <= ESPERA;
                end

                default: state <= ESPERA;
            endcase
        end
    end

endmodule


module fpu_add_sub (
    input wire sinal_a,
    input wire [7:0] expoente_a,
    input wire [23:0] mantissa_a,
    input wire sinal_b,
    input wire [7:0] expoente_b,
    input wire [23:0] mantissa_b,
    input wire subtrair,
    output wire sinal_resultado,
    output wire [7:0] expoente_resultado,
    output wire [27:0] mantissa_resultado // [27:26] parte inteira, [25:3] fracao, [2] G, [1] R, [0] S
);

// se os sinais diferem, eh subtracao efetiva
    wire subtracao_real = sinal_a ^ (sinal_b ^ subtrair);
    wire a_maior = (expoente_a > expoente_b) || (expoente_a == expoente_b && mantissa_a > mantissa_b);

    wire [7:0] expoente_maior = a_maior ? expoente_a : expoente_b;
    wire [23:0] mantissa_maior = a_maior ? mantissa_a : mantissa_b;
    wire [7:0] expoente_menor = a_maior ? expoente_b : expoente_a;
    wire [23:0] mantissa_menor = a_maior ? mantissa_b : mantissa_a;

    wire [7:0] diferenca_exp = expoente_maior - expoente_menor;


    // diferenca > 26 significa que o menor some inteiro no sticky
    wire [7:0] deslocamento = (diferenca_exp > 8'd26) ? 8'd27 : diferenca_exp;

    wire [50:0] mantissa_para_deslocar = {1'b0, mantissa_menor, 26'b0};
    wire [50:0] menor_deslocada;
    right_shift_51 deslocador (
        .entrada(mantissa_para_deslocar),
        .deslocamento(deslocamento[4:0]),
        .saida(menor_deslocada)
    );
    
    wire [23:0] mantissa_menor_alinhada = menor_deslocada[49:26];
    wire bit_guarda = menor_deslocada[25];
    wire bit_arred = menor_deslocada[24];
    wire forca_sticky = (diferenca_exp > 8'd26) & |mantissa_menor;
    wire bit_sticky = |menor_deslocada[23:0] | forca_sticky;

    wire [27:0] mantissa_maior_ext = {1'b0, mantissa_maior, 3'b000};
    wire [27:0] mantissa_menor_ext = {1'b0, mantissa_menor_alinhada, bit_guarda, bit_arred, bit_sticky};
    
    wire [27:0] mantissa_calc = subtracao_real ? (mantissa_maior_ext - mantissa_menor_ext)
                                    : (mantissa_maior_ext + mantissa_menor_ext);
       
    // caso especial: a - a = +0
    assign sinal_resultado = (subtracao_real && mantissa_maior == mantissa_menor && expoente_a == expoente_b) ?
                    1'b0
                    : (a_maior ? sinal_a : (sinal_b ^ subtrair));
                    
    assign expoente_resultado = expoente_maior;
    assign mantissa_resultado = mantissa_calc;

endmodule


module fpu_mul (
    input wire clock,
    input wire reset,
    input wire start,
    input wire sinal_a,
    input wire [7:0] expoente_a,
    input wire [23:0] mantissa_a,
    input wire sinal_b,
    input wire [7:0] expoente_b,
    input wire [23:0] mantissa_b,
    output reg busy,
    output reg done,
    output wire sinal_resultado,
    output wire [9:0] expoente_resultado,
    output wire [27:0] mantissa_resultado
);

    assign sinal_resultado = sinal_a ^ sinal_b;

    wire [9:0] expoente_a_ext = {2'b00, expoente_a};
    wire [9:0] expoente_b_ext = {2'b00, expoente_b};
    assign expoente_resultado = expoente_a_ext + expoente_b_ext - 10'd127;

    // shift-and-add sequencial, 24 ciclos
    reg [47:0] acumulador;
    reg [47:0] multiplicando;
    reg [23:0] multiplicador_bits;
    reg [4:0] contador;

    reg [1:0] state;
    localparam ESPERA = 2'd0;
    localparam CALCULA = 2'd1;
    localparam CONCLUI = 2'd2;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state <= ESPERA;
            busy <= 1'b0;
            done <= 1'b0;
            acumulador <= 48'd0;
            multiplicando <= 48'd0;
            multiplicador_bits <= 24'd0;
            contador <= 5'd0;
        end else begin
            case (state)
                ESPERA: begin
                    done <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        acumulador <= 48'd0;
                        multiplicando <= {24'd0, mantissa_a};
                        multiplicador_bits <= mantissa_b;
                        contador <= 5'd24;
                        state <= CALCULA;
                    end
                end

                CALCULA: begin
                    if (contador > 0) begin
                           // se o bit atual do multiplicador for 1, soma o multiplicando deslocado
                        if (multiplicador_bits[0])
                            acumulador <= acumulador + multiplicando;
                        multiplicando <= multiplicando << 1;
                        multiplicador_bits <= multiplicador_bits >> 1;
                        contador <= contador - 1;
                    end else begin
                        state <= CONCLUI;
                    end
                end

                CONCLUI: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ESPERA;
                end

                default: state <= ESPERA;
            endcase
        end
    end

    // bits GRS extraidos do produto de 48 bits
    wire bit_guarda = acumulador[22];
    wire bit_arred = acumulador[21];
    wire bit_sticky = |acumulador[20:0];

    assign mantissa_resultado = {acumulador[47:23], bit_guarda, bit_arred, bit_sticky};
endmodule


module fpu_div (
    input wire clock,
    input wire reset,
    input wire start,
    input wire sinal_a,
    input wire [7:0] expoente_a,
    input wire [23:0] mantissa_a,
    input wire sinal_b,
    input wire [7:0] expoente_b,
    input wire [23:0] mantissa_b,
    output reg busy,
    output reg done,
    output wire f_div_zero,
    output wire sinal_resultado,
    output wire [9:0] expoente_resultado,
    output wire [27:0] mantissa_resultado
);
    assign sinal_resultado = sinal_a ^ sinal_b;

     // o unpacker mapeia zero pra (exp=1, mant=0), entao mant=0 ja basta pra detectar
    assign f_div_zero = (mantissa_b == 24'd0) && (expoente_b == 8'd0);

    reg [4:0] zeros_a, zeros_b;
    always @(*) begin
        if (mantissa_a[23]) zeros_a = 5'd0;
        else if (mantissa_a[22]) zeros_a = 5'd1;
        else if (mantissa_a[21]) zeros_a = 5'd2;
        else if (mantissa_a[20]) zeros_a = 5'd3;
        else if (mantissa_a[19]) zeros_a = 5'd4;
        else if (mantissa_a[18]) zeros_a = 5'd5;
        else if (mantissa_a[17]) zeros_a = 5'd6;
        else if (mantissa_a[16]) zeros_a = 5'd7;
        else if (mantissa_a[15]) zeros_a = 5'd8;
        else if (mantissa_a[14]) zeros_a = 5'd9;
        else if (mantissa_a[13]) zeros_a = 5'd10;
        else if (mantissa_a[12]) zeros_a = 5'd11;
        else if (mantissa_a[11]) zeros_a = 5'd12;
        else if (mantissa_a[10]) zeros_a = 5'd13;
        else if (mantissa_a[9]) zeros_a = 5'd14;
        else if (mantissa_a[8]) zeros_a = 5'd15;
        else if (mantissa_a[7]) zeros_a = 5'd16;
        else if (mantissa_a[6]) zeros_a = 5'd17;
        else if (mantissa_a[5]) zeros_a = 5'd18;
        else if (mantissa_a[4]) zeros_a = 5'd19;
        else if (mantissa_a[3]) zeros_a = 5'd20;
        else if (mantissa_a[2]) zeros_a = 5'd21;
        else if (mantissa_a[1]) zeros_a = 5'd22;
        else if (mantissa_a[0]) zeros_a = 5'd23;
        else zeros_a = 5'd0;
    end
    
    always @(*) begin
        if (mantissa_b[23]) zeros_b = 5'd0;
        else if (mantissa_b[22]) zeros_b = 5'd1;
        else if (mantissa_b[21]) zeros_b = 5'd2;
        else if (mantissa_b[20]) zeros_b = 5'd3;
        else if (mantissa_b[19]) zeros_b = 5'd4;
        else if (mantissa_b[18]) zeros_b = 5'd5;
        else if (mantissa_b[17]) zeros_b = 5'd6;
        else if (mantissa_b[16]) zeros_b = 5'd7;
        else if (mantissa_b[15]) zeros_b = 5'd8;
        else if (mantissa_b[14]) zeros_b = 5'd9;
        else if (mantissa_b[13]) zeros_b = 5'd10;
        else if (mantissa_b[12]) zeros_b = 5'd11;
        else if (mantissa_b[11]) zeros_b = 5'd12;
        else if (mantissa_b[10]) zeros_b = 5'd13;
        else if (mantissa_b[9]) zeros_b = 5'd14;
        else if (mantissa_b[8]) zeros_b = 5'd15;
        else if (mantissa_b[7]) zeros_b = 5'd16;
        else if (mantissa_b[6]) zeros_b = 5'd17;
        else if (mantissa_b[5]) zeros_b = 5'd18;
        else if (mantissa_b[4]) zeros_b = 5'd19;
        else if (mantissa_b[3]) zeros_b = 5'd20;
        else if (mantissa_b[2]) zeros_b = 5'd21;
        else if (mantissa_b[1]) zeros_b = 5'd22;
        else if (mantissa_b[0]) zeros_b = 5'd23;
        else zeros_b = 5'd0;
    end

    wire [23:0] mant_a_norm = mantissa_a << zeros_a;
    wire [23:0] mant_b_norm = mantissa_b << zeros_b;

    wire [9:0] expoente_a_ext = {2'b00, expoente_a};
    wire [9:0] expoente_b_ext = {2'b00, expoente_b};
    wire [9:0] expo_a_norm = expoente_a_ext - {5'b0, zeros_a};
    wire [9:0] expo_b_norm = expoente_b_ext - {5'b0, zeros_b};

    assign expoente_resultado = expo_a_norm - expo_b_norm + 10'd127;

    // divisao por restauracao
    reg [24:0] acumulador;
    reg [25:0] quociente;
    reg [24:0] divisor_reg;
    reg [4:0] contador;
    reg sticky_reg;

    reg [2:0] state;
    localparam ESPERA = 3'd0;
    localparam SUBTRAI = 3'd1;
    localparam RESTAURA = 3'd2;
    localparam DESLOCA = 3'd3;
    localparam AJUSTA_STICKY = 3'd4;
    localparam FIM_DIV = 3'd5;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state <= ESPERA;
            busy <= 1'b0;
            done <= 1'b0;
            contador <= 5'd0;
            acumulador <= 25'd0;
            quociente <= 26'd0;
            divisor_reg <= 25'd0;
            sticky_reg <= 1'b0;
        end else begin
            case (state)
                ESPERA: begin
                    done <= 1'b0;
                    if (start && !f_div_zero) begin
                        busy <= 1'b1;
                        acumulador <= {1'b0, mant_a_norm};
                        quociente <= 26'd0;
                        divisor_reg <= {1'b0, mant_b_norm};
                        contador <= 5'd26;
                        sticky_reg <= 1'b0;
                        state <= SUBTRAI;
                    end else if (start && f_div_zero) begin
                        done <= 1'b1;
                    end
                end

                SUBTRAI: begin
                    acumulador <= acumulador - divisor_reg;
                    state <= RESTAURA;
                end

                RESTAURA: begin
                    if (acumulador[24]) begin
                        acumulador <= acumulador + divisor_reg;
                        quociente <= {quociente[24:0], 1'b0};
                    end else begin
                        quociente <= {quociente[24:0], 1'b1};
                    end

                    if (contador == 5'd1) begin
                        state <= AJUSTA_STICKY;
                    end else begin
                        contador <= contador - 1;
                        state <= DESLOCA;
                    end
                end

                DESLOCA: begin
                    acumulador <= {acumulador[23:0], 1'b0};
                    state <= SUBTRAI;
                end

                AJUSTA_STICKY: begin
                    sticky_reg <= (acumulador != 25'd0);
                    state <= FIM_DIV;
                end

                FIM_DIV: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ESPERA;
                end

                default: state <= ESPERA;
            endcase
        end
    end

     // monta o formato de 28 bits esperado pelo normalizador
    assign mantissa_resultado = {1'b0, quociente[25:0], sticky_reg};
endmodule


module fpu_cmp (
    input wire sinal_a,
    input wire [7:0] expoente_a,
    input wire [23:0] mantissa_a,
    input wire a_eh_zero,
    input wire sinal_b,
    input wire [7:0] expoente_b,
    input wire [23:0] mantissa_b,
    input wire b_eh_zero,
    input wire faz_menor_que,
    output wire [31:0] resultado_comp
);
    wire a_nan = (expoente_a == 8'hFF) && (mantissa_a[22:0] != 0);
    wire b_nan = (expoente_b == 8'hFF) && (mantissa_b[22:0] != 0);
    wire algum_nan = a_nan | b_nan;

    wire ambos_zero = a_eh_zero & b_eh_zero;

    wire iguais_sem_nan = ambos_zero |
        (sinal_a == sinal_b && expoente_a == expoente_b && mantissa_a == mantissa_b);

    wire sao_iguais = algum_nan ? 1'b0 : iguais_sem_nan;
    wire sinais_dif_menor = (sinal_a & ~sinal_b) & ~ambos_zero;
    wire modulo_a_menor_b = (expoente_a < expoente_b) |
        (expoente_a == expoente_b && mantissa_a < mantissa_b);
    wire modulo_a_maior_b = (expoente_a > expoente_b) |
        (expoente_a == expoente_b && mantissa_a > mantissa_b);
    wire positivos_menor = (~sinal_a & ~sinal_b) & modulo_a_menor_b;
    wire negativos_menor = (sinal_a & sinal_b) & modulo_a_maior_b;

    wire menor_sem_nan = sinais_dif_menor | positivos_menor | negativos_menor;
    wire a_menor_b = algum_nan ? 1'b0 : menor_sem_nan;

    wire comparacao_ok = faz_menor_que ? a_menor_b : sao_iguais;
    assign resultado_comp = comparacao_ok ? 32'h3F800000 : 32'h00000000;

endmodule


module fpu_normalizer (
    input wire sinal,
    input wire [9:0] expoente_entrada, // 10 bits para acomodar overflow de expoente
    input wire [27:0] mantissa_entrada, // [27:26] inteiro, [25:3] fracao, [2] G, [1] R, [0] S
    output reg sinal_resultado,
    output reg [7:0] expoente_resultado,
    output reg [22:0] fracao_resultado,
    output reg f_overflow,
    output reg f_underflow,
    output reg f_inexact
);
    wire [27:0] mantissa_esq;
    wire [27:0] mantissa_dir;
    reg [4:0] left_shift;

    // encoder de prioridade para saber quantos bits shiftar pra esquerda
    always @(*) begin
        if (mantissa_entrada[27] || mantissa_entrada[26]) left_shift = 5'd0;
        else if (mantissa_entrada[25]) left_shift = 5'd1;
        else if (mantissa_entrada[24]) left_shift = 5'd2;
        else if (mantissa_entrada[23]) left_shift = 5'd3;
        else if (mantissa_entrada[22]) left_shift = 5'd4;
        else if (mantissa_entrada[21]) left_shift = 5'd5;
        else if (mantissa_entrada[20]) left_shift = 5'd6;
        else if (mantissa_entrada[19]) left_shift = 5'd7;
        else if (mantissa_entrada[18]) left_shift = 5'd8;
        else if (mantissa_entrada[17]) left_shift = 5'd9;
        else if (mantissa_entrada[16]) left_shift = 5'd10;
        else if (mantissa_entrada[15]) left_shift = 5'd11;
        else if (mantissa_entrada[14]) left_shift = 5'd12;
        else if (mantissa_entrada[13]) left_shift = 5'd13;
        else if (mantissa_entrada[12]) left_shift = 5'd14;
        else if (mantissa_entrada[11]) left_shift = 5'd15;
        else if (mantissa_entrada[10]) left_shift = 5'd16;
        else if (mantissa_entrada[9]) left_shift = 5'd17;
        else if (mantissa_entrada[8]) left_shift = 5'd18;
        else if (mantissa_entrada[7]) left_shift = 5'd19;
        else if (mantissa_entrada[6]) left_shift = 5'd20;
        else if (mantissa_entrada[5]) left_shift = 5'd21;
        else if (mantissa_entrada[4]) left_shift = 5'd22;
        else if (mantissa_entrada[3]) left_shift = 5'd23;
        else if (mantissa_entrada[2]) left_shift = 5'd24;
        else if (mantissa_entrada[1]) left_shift = 5'd25;
        else if (mantissa_entrada[0]) left_shift = 5'd26;
        else left_shift = 5'd0;
    end

    right_shift_28 desloca_1_dir (
        .entrada(mantissa_entrada),
        .deslocamento(5'd1),
        .saida(mantissa_dir)
    );
    
    left_shift_28 desloca_norm_esq (
        .entrada(mantissa_entrada),
        .deslocamento(left_shift),
        .saida(mantissa_esq)
    );
    
    reg [27:0] mantissa_ajustada;
    reg [11:0] expoente_ajustado;
    reg [11:0] expoente_in_sinalizado;

    always @(*) begin
        expoente_in_sinalizado = {{2{expoente_entrada[9]}}, expoente_entrada};
        if (mantissa_entrada == 28'd0) begin
            mantissa_ajustada = 28'd0;
            expoente_ajustado = 12'd0;
        end else begin
            if (mantissa_entrada[27]) begin
                // carry do somador: shift direita e ajusta expoente
                mantissa_ajustada = mantissa_dir;
                mantissa_ajustada[0] = mantissa_dir[0] | mantissa_entrada[0];
                expoente_ajustado = expoente_in_sinalizado + 12'd1;
            end else if (mantissa_entrada[26]) begin
                mantissa_ajustada = mantissa_entrada;
                expoente_ajustado = expoente_in_sinalizado;
            end else begin
                // normaliza pra esquerda ate bit 26
                mantissa_ajustada = mantissa_esq;
                expoente_ajustado = expoente_in_sinalizado - {7'd0, left_shift};
            end
        end
    end

    wire [11:0] dist_subnormal = 12'd1 - expoente_ajustado;
    
    // Checagem de numero negativo puro
    wire eh_subnormal = expoente_ajustado[11] || (expoente_ajustado == 12'd0);

    wire [4:0] desloca_sub;
    assign desloca_sub = (!eh_subnormal) ? 5'd0 :
                         (dist_subnormal > 12'd27) ? 5'd27 : dist_subnormal[4:0];

    wire [27:0] mant_pre_arred_sub;
    right_shift_28 desloca_sub_inst (
        .entrada(mantissa_ajustada),
        .deslocamento(desloca_sub),
        .saida(mant_pre_arred_sub)
    );

    wire [31:0] mascara_sticky = (32'd1 << desloca_sub) - 1'b1;
    wire sticky_extra = |(mantissa_ajustada & mascara_sticky[27:0]);

    wire [27:0] mant_para_arredondar = eh_subnormal ? 
        {mant_pre_arred_sub[27:1], mant_pre_arred_sub[0] | sticky_extra} : 
        mantissa_ajustada;

    wire guarda = mant_para_arredondar[2];
    wire arredonda = mant_para_arredondar[1];
    wire sticky = mant_para_arredondar[0];
    wire inexato_calculado = guarda | arredonda | sticky;

    wire sobe_arred = guarda & (arredonda | sticky | mant_para_arredondar[3]); 
    wire [24:0] mantissa_arredondada = {1'b0, mant_para_arredondar[26:3]} + sobe_arred;

    reg [11:0] exp_final;
    reg [24:0] frac_final;

    always @(*) begin
        sinal_resultado = sinal;
        f_overflow = 1'b0;
        f_underflow = 1'b0;
        f_inexact = inexato_calculado;
        expoente_resultado = 8'd0;
        fracao_resultado = 23'd0;
        
        // Inicializacao movida para ca
        exp_final = eh_subnormal ? 12'd0 : expoente_ajustado;
        frac_final = mantissa_arredondada;

        if (mantissa_entrada == 28'd0) begin
            expoente_resultado = 8'd0;
            fracao_resultado = 23'd0;
            f_inexact = 1'b0;
        end else begin
            if (frac_final[24]) begin 
                // arredondamento gerou carry, re-normaliza
                frac_final = {1'b0, frac_final[24:1]};
                if (eh_subnormal) begin
                    exp_final = 12'd1; 
                end else begin
                    exp_final = exp_final + 12'd1;
                end
            end

            // Checagem segura de overflow e underflow com bit de sinal (bit 11)
            if (!exp_final[11] && exp_final >= 12'd255) begin
                f_overflow = 1'b1;
                f_inexact = 1'b1;
                expoente_resultado = 8'hFF;
                fracao_resultado = 23'd0;
            end else if (exp_final[11] || exp_final == 12'd0) begin
                f_underflow = inexato_calculado;
                expoente_resultado = 8'd0;
                fracao_resultado = frac_final[22:0];
            end else begin
                expoente_resultado = exp_final[7:0];
                fracao_resultado = frac_final[22:0];
            end
        end
    end

endmodule


module fpu_unpacker (
    input wire [31:0] operando,
    output wire sinal,
    output wire [7:0] expoente,
    output wire [23:0] mantissa,
    output wire eh_zero,
    output wire eh_infinito,
    output wire eh_nan,
    output wire eh_subnormal
);
    wire [7:0] expoente_bruto = operando[30:23];
    wire [22:0] fracao = operando[22:0];

    assign sinal = operando[31];
    assign eh_zero = (expoente_bruto == 8'h00) && (fracao == 23'h000000);
    assign eh_subnormal = (expoente_bruto == 8'h00) && (fracao != 23'h000000);
    assign eh_infinito = (expoente_bruto == 8'hFF) && (fracao == 23'h000000);
    assign eh_nan = (expoente_bruto == 8'hFF) && (fracao != 23'h000000);
    

    // subnormais usam exp = 1 internamente (mesmo bias, bit implicito = 0)
    assign expoente = (expoente_bruto == 8'h00) ? 8'h01 : expoente_bruto;
    assign mantissa = (expoente_bruto == 8'h00) ? {1'b0, fracao} : {1'b1, fracao};
endmodule


module left_shift_28 (
    input wire [27:0] entrada,
    input wire [4:0] deslocamento,
    output wire [27:0] saida
);
    wire [27:0] s0, s1, s2, s3, s4;

    assign s0 = deslocamento[0] ? {entrada[26:0], 1'b0} : entrada;
    assign s1 = deslocamento[1] ? {s0[25:0], 2'b0} : s0;
    assign s2 = deslocamento[2] ? {s1[23:0], 4'b0} : s1;
    assign s3 = deslocamento[3] ? {s2[19:0], 8'b0} : s2;
    assign s4 = deslocamento[4] ? {s3[11:0], 16'b0} : s3;
    
    assign saida = s4;
endmodule


module right_shift_28 (
    input wire [27:0] entrada,
    input wire [4:0] deslocamento,
    output wire [27:0] saida
);
    wire [27:0] s0, s1, s2, s3, s4;

    assign s0 = deslocamento[0] ? {1'b0, entrada[27:1]} : entrada;
    assign s1 = deslocamento[1] ? {2'b0, s0[27:2]} : s0;
    assign s2 = deslocamento[2] ? {4'b0, s1[27:4]} : s1;
    assign s3 = deslocamento[3] ? {8'b0, s2[27:8]} : s2;
    assign s4 = deslocamento[4] ? {16'b0, s3[27:16]} : s3;
    
    assign saida = s4;
endmodule


module right_shift_51 (
    input wire [50:0] entrada,
    input wire [4:0] deslocamento,
    output wire [50:0] saida
);
    wire [50:0] s0, s1, s2, s3, s4;

    assign s0 = deslocamento[0] ? {1'b0, entrada[50:1]} : entrada;
    assign s1 = deslocamento[1] ? {2'b0, s0[50:2]} : s0;
    assign s2 = deslocamento[2] ? {4'b0, s1[50:4]} : s1;
    assign s3 = deslocamento[3] ? {8'b0, s2[50:8]} : s2;
    assign s4 = deslocamento[4] ? {16'b0, s3[50:16]} : s3;
    
    assign saida = s4;
endmodule