module df #(
    parameter N = 8
)(
    input wire clk,
    input wire rst,
    // Carregamento inicial
    input wire load_m, // M <- divisor
    input wire [N-1:0] divisor,
    input wire load_aq, // A <-0 , Q ← dividend
    input wire [N-1:0] dividend,
    // Controles da UC
    input wire shift_aq, // desloca {A,Q} 1 bit a esquerda
    input wire update_a, // escreve resultado da ULA em {A,Q}
    // Sa´ıdas
    output wire [N-1:0] M,
    output wire [N-1:0] A, // resto parcial (MSBs de {A,Q})
    output wire [N-1:0] Q, // quociente (LSBs de {A,Q})
    output wire negative // (A-M) < 0 -> UC observa (opcional)
);

wire [N-1:0] M_reg;
wire [N-1:0] A_reg;
wire [N-1:0] Q_reg;

wire [N-1:0] alu_result;
wire alu_cout;
wire alu_overflow;
wire alu_negative;

add_sub #(.N(N)) alu (
    .a(A_reg),
    .b(M_reg),
    .sub(1'b1),
    .result(alu_result),
    .cout(alu_cout),
    .overflow(alu_overflow),
    .negative(alu_negative)
);

wire [N-1:0] shiftA = {A_reg[N-2:0], Q_reg[N-1]};
wire [N-1:0] shiftQ = {Q_reg[N-2:0], 1'b0};

wire load_A = load_aq | shift_aq | update_a;
wire load_Q = load_aq | shift_aq | update_a;

wire [N-1:0] A_next = load_aq ? {N{1'b0}} :
                      shift_aq ? shiftA :
                      update_a ? alu_result :
                      A_reg;

wire [N-1:0] Q_next = load_aq ? dividend :
                      shift_aq ? shiftQ :
                      update_a ? {Q_reg[N-1:1], ~alu_negative} :
                      Q_reg;

register #(.N(N)) regM (
    .clk(clk),
    .rst(rst),
    .load(load_m),
    .data_in(divisor),
    .data_out(M_reg)
);

register #(.N(N)) regA (
    .clk(clk),
    .rst(rst),
    .load(load_A),
    .data_in(A_next),
    .data_out(A_reg)
);

register #(.N(N)) regQ (
    .clk(clk),
    .rst(rst),
    .load(load_Q),
    .data_in(Q_next),
    .data_out(Q_reg)
);

assign M = M_reg;
assign A = A_reg;
assign Q = Q_reg;
assign negative = alu_negative;

endmodule