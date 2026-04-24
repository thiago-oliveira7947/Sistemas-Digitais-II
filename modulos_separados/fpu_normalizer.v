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