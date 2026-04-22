module fpu_normalizer (
    input  wire        sign,
    input  wire [9:0]  exp_in,    // 10 bits (recebe do ADD/SUB ou MUL)
    input  wire [27:0] mant_in,   // Formato: [27:26] Int, [25:3] Frac, [2] G, [1] R, [0] S
    
    output reg         res_sign,
    output reg  [7:0]  res_exp,
    output reg  [22:0] res_frac,
    output reg         f_overflow,
    output reg         f_underflow,
    output reg         f_inexact
);

    // --- Fios de conexão com os Shifters ---
    wire [27:0] mant_left_out;
    wire [27:0] mant_right_out;
    reg  [4:0]  left_shift_amt;
    
    // --- Variáveis internas da FSM ---
    reg [27:0] shifted_mant;
    reg signed [11:0] adj_exp; // 12 bits com sinal para lidar com underflow matemático
    
    reg        guard, round, sticky;
    reg        round_up;
    reg [24:0] rounded_mant;   // 25 bits para capturar um possível carry no arredondamento

    // 1. Codificador de Prioridade (Substitui o 'for' loop)
    // Calcula quantos zeros à esquerda existem a partir do bit 25
    always @(*) begin
        if      (mant_in[25]) left_shift_amt = 5'd1;
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

    // 2. Instanciação dos Barrel Shifters combinacionais
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

    // 3. Bloco Principal de Normalização
    always @(*) begin
        // Reset padrão para evitar latches
        res_sign    = sign;
        res_exp     = 8'd0;
        res_frac    = 23'd0;
        f_overflow  = 1'b0;
        f_underflow = 1'b0;
        f_inexact   = 1'b0;
        adj_exp     = {2'b00, exp_in}; 

        if (mant_in == 28'd0) begin
            res_exp  = 8'd0;
            res_frac = 23'd0;
            shifted_mant = 28'd0; // Limpa para evitar lixo
        end else begin
            if (mant_in[27] == 1'b1) begin
                // Recebe o dado do shifter para a direita
                shifted_mant = mant_right_out;
                // Preserva o bit que seria perdido fazendo um OR com o Sticky anterior
                shifted_mant[0] = mant_right_out[0] | mant_in[0]; 
                adj_exp = exp_in + 1;
            end else if (mant_in[26] == 1'b1) begin
                // Ja normalizado
                shifted_mant = mant_in;
                adj_exp = exp_in;
            end else begin
                // x < 1. Recebe o dado do shifter para a esquerda.
                shifted_mant = mant_left_out;
                adj_exp = exp_in - left_shift_amt;
            end

            guard  = shifted_mant[2];
            round  = shifted_mant[1];
            sticky = shifted_mant[0];
            
            f_inexact = guard | round | sticky;

            // Arredonda para cima se Guard é 1 e (Round ou Sticky são 1, ou se o bit LSB da fração for 1)
            round_up = guard & (round | sticky | shifted_mant[3]);

            rounded_mant = {1'b0, shifted_mant[26:3]} + round_up;

            // Checa o arredondamento
            if (rounded_mant[24] == 1'b1) begin
                // Concatenação substitui o operador de shift (>>)
                rounded_mant = {1'b0, rounded_mant[24:1]};
                adj_exp = adj_exp + 1;
            end

            // Verificacao de overflow e underflow
            if ($signed(adj_exp) >= 255) begin
                f_overflow = 1'b1;
                res_exp    = 8'hFF;
                res_frac   = 23'd0;
            end else if ($signed(adj_exp) <= 0) begin
                f_underflow = 1'b1;
                res_exp     = 8'd0;
                res_frac    = 23'd0; 
            end else begin
                // Normalizacao
                res_exp  = adj_exp[7:0];
                res_frac = rounded_mant[22:0];
            end
        end
    end

endmodule