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