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

    reg [4:0]  shift_left;
    reg [27:0] shifted_mant;
    reg signed [11:0] adj_exp; // 12 bits com sinal para lidar com underflow matemático
    
    reg        guard, round, sticky;
    reg        round_up;
    reg [24:0] rounded_mant;   // 25 bits para capturar um possível carry no arredondamento
    
    integer i;

    always @(*) begin
        res_sign    = sign;
        res_exp     = 8'd0;
        res_frac    = 23'd0;
        f_overflow  = 1'b0;
        f_underflow = 1'b0;
        f_inexact   = 1'b0;
        shift_left  = 5'd0;
        adj_exp     = {2'b00, exp_in}; 

        if (mant_in == 28'd0) begin
            res_exp  = 8'd0;
            res_frac = 23'd0;
        end else begin
            if (mant_in[27] == 1'b1) begin
                shifted_mant = mant_in >> 1;
                // Preserva o bit que seria perdido fazendo um OR com o Sticky anterior
                shifted_mant[0] = mant_in[0] | mant_in[1]; 
                adj_exp = exp_in + 1;
            end else if (mant_in[26] == 1'b1) begin
                // Ja normalizado
                shifted_mant = mant_in;
                adj_exp = exp_in;
            end else begin
                // x < 1. Desloca para a esquerda.
                shift_left = 5'd26;
                for (i = 25; i >= 0; i = i - 1) begin
                    if (mant_in[i] == 1'b1 && shift_left == 5'd26) begin
                        shift_left = 26 - i;
                    end
                end
                shifted_mant = mant_in << shift_left;
                adj_exp = exp_in - shift_left;
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
                // Se gerar carry
                rounded_mant = rounded_mant >> 1;
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