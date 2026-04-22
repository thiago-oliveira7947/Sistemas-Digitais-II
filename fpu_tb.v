`timescale 1ns / 1ps

module fpu_tb;

    // Sinais do Testbench
    reg clock;
    reg reset;
    reg start;
    reg [31:0] a;
    reg [31:0] b;
    reg [2:0]  op;

    wire [31:0] c;
    wire busy;
    wire done;
    wire f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact;

    // Instanciação da FPU
    fpu uut (
        .clock(clock), .reset(reset), .start(start),
        .a(a), .b(b), .op(op),
        .c(c), .busy(busy), .done(done),
        .f_inv_op(f_inv_op), .f_div_zero(f_div_zero),
        .f_overflow(f_overflow), .f_underflow(f_underflow), .f_inexact(f_inexact)
    );

    // Gerador de Clock (10ns de período)
    always #5 clock = ~clock;

    // Task para automatizar os testes e exibir no console
    task run_test;
        input [31:0]   val_a;
        input [31:0]   val_b;
        input [2:0]    val_op;
        input [14*8:1] test_name; // String descritiva do teste
        begin
            a = val_a;
            b = val_b;
            op = val_op;
            
            @(posedge clock);
            start = 1;
            @(posedge clock);
            start = 0;

            wait(done == 1'b1);
            
            $display("[%14s] A: %h, B: %h | C: %h", test_name, a, b, c);
            $display("                 Flags -> Inv:%b Div0:%b OVF:%b UNF:%b Inex:%b\n", 
                      f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact);
            
            @(posedge clock); 
        end
    endtask

    initial begin
        $dumpfile("fpu_waveforms.vcd");
        $dumpvars(0, fpu_tb);

        clock = 0; reset = 1; start = 0;
        a = 32'd0; b = 32'd0; op = 3'b000;

        #20; reset = 0; #20;

        $display("\n=======================================================");
        $display("   TESTES DE FLAGS E CASOS EXTREMOS (IEEE 754 FPU)     ");
        $display("=======================================================\n");

        // ----------------------------------------------------------------
        // 1. TESTES DE OPERAÇÃO INVÁLIDA (f_inv_op) - Deve retornar NaN (7FC00000)
        // ----------------------------------------------------------------
        // 0.0 * +Infinito
        run_test(32'h00000000, 32'h7F800000, 3'b010, "INV: 0 * Inf");
        
        // 0.0 / 0.0
        run_test(32'h00000000, 32'h00000000, 3'b011, "INV: 0 / 0");
        
        // +Infinito - +Infinito
        run_test(32'h7F800000, 32'h7F800000, 3'b001, "INV: Inf - Inf");
        
        // Propagação de NaN (NaN + 1.0)
        run_test(32'h7FC00000, 32'h3F800000, 3'b000, "INV: NaN + 1.0");

        // ----------------------------------------------------------------
        // 2. TESTES DE DIVISÃO POR ZERO (f_div_zero) - Deve retornar Infinito (7F800000)
        // ----------------------------------------------------------------
        // 1.0 / 0.0
        run_test(32'h3F800000, 32'h00000000, 3'b011, "DIV0: 1.0 / 0");

        // ----------------------------------------------------------------
        // 3. TESTES DE OVERFLOW (f_overflow) - Deve retornar Infinito
        // ----------------------------------------------------------------
        // Max Float (7F7FFFFF) * 2.0 (40000000) -> Expoente estoura 254
        run_test(32'h7F7FFFFF, 32'h40000000, 3'b010, "OVF: Max * 2.0");
        
        // Max Float (7F7FFFFF) + Max Float (7F7FFFFF) -> Estouro na adição
        run_test(32'h7F7FFFFF, 32'h7F7FFFFF, 3'b000, "OVF: Max + Max");

        // ----------------------------------------------------------------
        // 4. TESTES DE UNDERFLOW (f_underflow) - Deve retornar Zero (00000000)
        // ----------------------------------------------------------------
        // Min Normal Float (00800000) / 2.0 (40000000) -> Expoente cai abaixo de 1
        run_test(32'h00800000, 32'h40000000, 3'b011, "UNF: Min / 2.0");

        // ----------------------------------------------------------------
        // 5. TESTES DE RESULTADO INEXATO (f_inexact)
        // ----------------------------------------------------------------
        // 1.0 / 3.0 -> Gera dízima binária (0.010101...), precisa descartar bits
        run_test(32'h3F800000, 32'h40400000, 3'b011, "INEXACT: 1/3");

        // ----------------------------------------------------------------
        // 6. CASOS EXTREMOS DE COMPARAÇÃO (EQ e SLT)
        // ----------------------------------------------------------------
        // +0.0 == -0.0 (Apesar de sinais diferentes, IEEE 754 diz que são iguais)
        // A = 00000000 (+0), B = 80000000 (-0). Esperado C = 3F800000 (True)
        run_test(32'h00000000, 32'h80000000, 3'b100, "EQ: +0 == -0");
        
        // -5.0 < -2.0 (Checando lógica de menor que com números negativos)
        // A = C0A00000 (-5), B = C0000000 (-2). Esperado C = 3F800000 (True)
        run_test(32'hC0A00000, 32'hC0000000, 3'b101, "SLT: -5 < -2");

        // ----------------------------------------------------------------
        // 7. TESTE ESPECIAL: NaN == NaN
        // De acordo com IEEE 754, NaN != NaN sempre. 
        // O resultado deve ser C = NaN (ou 0.0) e f_inv_op = 1.
        // ----------------------------------------------------------------
        run_test(32'h7FC00000, 32'h7FC00000, 3'b100, "EQ: NaN == NaN");


        $display("=======================================================");
        $display("                 FIM DA BATERIA DE TESTES              ");
        $display("=======================================================\n");
        
        $finish;
    end

endmodule