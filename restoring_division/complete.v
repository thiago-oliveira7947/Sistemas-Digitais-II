module register #(
    parameter N = 8
)(
    input wire clk,
    input wire rst, // reset
    input wire load, // load
    input wire [N-1:0] data_in,
    output reg [N-1:0] data_out
);

always @(posedge clk or posedge rst) begin
    if (rst)
        data_out <= {N{1'b0}};
    else if (load)
        data_out <= data_in;
end

endmodule

module shift_left #(
    parameter N = 8
)(
    input wire clk,
    input wire rst, // reset
    input wire load, // load
    input wire shift, // desloca para a esquerda
    input wire [N-1:0] data_in,
    output reg [N-1:0] data_out
);

always @(posedge clk or posedge rst) begin
    if (rst)
        data_out <= {N{1'b0}};
    else if (load)
        data_out <= data_in;
    else if (shift)
        data_out <= {data_out[N-2:0], 1'b0};
end

endmodule

module add_sub #(
    parameter N = 8
)(
    input wire [N-1:0] a,
    input wire [N-1:0] b,
    input wire sub, // 0: soma (A+B), 1: subtração (A-B)
    output wire [N-1:0] result,
    output wire cout, // carry out
    output wire overflow, // overflow em complemento de 2
    output wire negative // result[N-1]: resultado negativo
);

wire [N-1:0] b_xor;
assign b_xor = b ^ {N{sub}};

wire [N:0] sum_full;
assign sum_full = {1'b0, a} + {1'b0, b_xor} + {{N{1'b0}}, sub};

assign result = sum_full[N-1:0];
assign cout = sum_full[N];

assign overflow = (a[N-1] & b_xor[N-1] & ~result[N-1]) |
                  (~a[N-1] & ~b_xor[N-1] & result[N-1]);

assign negative = result[N-1];

endmodule

module df #(
    parameter N = 8
)(
    input wire clk,
    input wire rst,
    // Carregamento inicial
    input wire load_m, // M <- divisor
    input wire [N-1:0] divisor,
    input wire load_aq, // A <-0 , Q <- dividend
    input wire [N-1:0] dividend,
    // Controles da UC
    input wire shift_aq, // desloca {A,Q} 1 bit a esquerda
    input wire update_a, // escreve resultado da ULA em {A,Q}
   
    // Saídas
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

    wire [N-1:0] A_next = load_aq  ? {N{1'b0}} :
                          shift_aq ? shiftA :
                          update_a ? (alu_cout ? alu_result : A_reg) : 
                          A_reg;
                          

    wire [N-1:0] Q_next = load_aq  ? dividend :
                          shift_aq ? shiftQ :
                          update_a ? {Q_reg[N-1:1], alu_cout} : 
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
    
    assign negative = ~alu_cout; 

endmodule

module uc #(
    parameter N = 24
)(
    input wire clk,
    input wire rst,
    input wire start,

    output reg load_m,
    output reg load_aq,
    output reg shift_aq,
    output reg update_a,
    output wire done
);

    localparam IDLE   = 3'b000,
               LOAD   = 3'b001,
               SHIFT  = 3'b010,
               UPDATE = 3'b011,
               DONE_S = 3'b100;

    wire [2:0] state;
    reg  [2:0] next_state;


    wire [N-1:0] count;
    reg  [N-1:0] count_next;
    wire count_load;


    always @(*) begin
        load_m   = 1'b0;
        load_aq  = 1'b0;
        shift_aq = 1'b0;
        update_a = 1'b0;

        next_state = state;
        count_next = count;

        case (state)
            IDLE: begin
                if (start) begin
                    next_state = LOAD;
                end
            end

            LOAD: begin
                load_m  = 1'b1;
                load_aq = 1'b1;
                next_state = SHIFT;
                count_next = N;
            end

            SHIFT: begin
                shift_aq = 1'b1;
                next_state = UPDATE;
            end


            UPDATE: begin
                update_a = 1'b1;

                count_next = count - 1;
                if (count > 1)
                    next_state = SHIFT;
                else
                    next_state = DONE_S;
            end
            DONE_S: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end


    assign count_load = (state == LOAD) | (state == UPDATE);
    assign done = (state == DONE_S);

    register #(.N(3)) state_reg (
        .clk(clk),
        .rst(rst),
        .load(1'b1),
        .data_in(next_state),
        .data_out(state)
    );
    register #(.N(N)) count_reg (
        .clk(clk),
        .rst(rst),
        .load(count_load),
        .data_in(count_next),
        .data_out(count)
    );

endmodule


module restoring_div #(
    parameter N = 8
)(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [N-1:0] dividend, // dividendo (N bits)
    input wire [N-1:0] divisor, // divisor (N bits)
    output wire [N-1:0] quotient, // quociente
    output wire [N-1:0] remainder, // resto
    output wire done
);

wire load_m_w;
wire load_aq_w;
wire shift_aq_w;
wire update_a_w;
wire done_w;

wire [N-1:0] M_w;
wire [N-1:0] A_w;
wire [N-1:0] Q_w;
wire negative_w;

uc #(.N(N)) uc_inst (
    .clk(clk),
    .rst(rst),
    .start(start),
    .load_m(load_m_w),
    .load_aq(load_aq_w),
    .shift_aq(shift_aq_w),
    .update_a(update_a_w),
    .done(done_w)
);

df #(.N(N)) df_inst (
    .clk(clk),
    .rst(rst),
    .load_m(load_m_w),
    .divisor(divisor),
    .load_aq(load_aq_w),
    .dividend(dividend),
    .shift_aq(shift_aq_w),
    .update_a(update_a_w),
    .M(M_w),
    .A(A_w),
    .Q(Q_w),
    .negative(negative_w)
);

assign quotient  = Q_w;
assign remainder = A_w;
assign done = done_w;

endmodule
