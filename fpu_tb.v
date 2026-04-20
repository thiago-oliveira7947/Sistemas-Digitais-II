// =============================================================================
// Testbench para FPU - PCS-3225 EP01
// Testa: ADD, SUB, MUL, DIV, EQ, SLT + casos especiais + flags
// =============================================================================

`timescale 1ns/1ps

module tb_fpu;

// Entradas
reg        clock, reset, start;
reg [31:0] a, b;
reg [2:0]  op;

// Saidas
wire [31:0] c;
wire        busy, done;
wire        f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact;

// Instancia a FPU
fpu dut (
    .clock(clock), .reset(reset), .start(start),
    .a(a), .b(b), .op(op),
    .c(c),
    .busy(busy), .done(done),
    .f_inv_op(f_inv_op), .f_div_zero(f_div_zero),
    .f_overflow(f_overflow), .f_underflow(f_underflow),
    .f_inexact(f_inexact)
);

// Clock: periodo de 10ns
initial clock = 0;
always #5 clock = ~clock;

// Tarefa para executar uma operacao e verificar o resultado
integer pass_count, fail_count;

task run_op;
    input [31:0] in_a, in_b;
    input [2:0]  in_op;
    input [31:0] expected;
    input        chk_inv, chk_divz, chk_ovf, chk_udf, chk_inex;
    input [63:0] test_name; // ignorado, apenas para referencia
    begin
        @(negedge clock);
        a     = in_a;
        b     = in_b;
        op    = in_op;
        start = 1;
        @(negedge clock);
        start = 0;

        // Aguarda done (com timeout de 200 ciclos)
        begin : wait_done
            integer timeout;
            timeout = 0;
            while (!done && timeout < 200) begin
                @(negedge clock);
                timeout = timeout + 1;
            end
            if (timeout >= 200) begin
                $display("TIMEOUT na operacao op=%0b a=%h b=%h", in_op, in_a, in_b);
                fail_count = fail_count + 1;
                disable wait_done;
            end
        end

        // Verifica resultado
        if (c !== expected) begin
            $display("FAIL: op=%0b a=%h b=%h | got=%h expected=%h",
                     in_op, in_a, in_b, c, expected);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: op=%0b a=%h b=%h => %h", in_op, in_a, in_b, c);
            pass_count = pass_count + 1;
        end

        // Verifica flags (apenas as que foram especificadas)
        if (chk_inv && !f_inv_op)
            $display("  FLAG MISS: f_inv_op esperado");
        if (chk_divz && !f_div_zero)
            $display("  FLAG MISS: f_div_zero esperado");
        if (chk_ovf && !f_overflow)
            $display("  FLAG MISS: f_overflow esperado");
        if (chk_udf && !f_underflow)
            $display("  FLAG MISS: f_underflow esperado");
        if (chk_inex && !f_inexact)
            $display("  FLAG MISS: f_inexact esperado");

        @(negedge clock); // pequena pausa entre operacoes
    end
endtask

initial begin
    pass_count = 0;
    fail_count = 0;

    // Reset
    reset = 1; start = 0; a = 0; b = 0; op = 0;
    repeat(3) @(negedge clock);
    reset = 0;
    @(negedge clock);

    $display("=== Testes de Adicao ===");
    // 1.0 + 1.0 = 2.0
    run_op(32'h3F800000, 32'h3F800000, 3'b000, 32'h40000000,
           0,0,0,0,0, "1+1=2   ");
    // 1.5 + 1.5 = 3.0
    run_op(32'h3FC00000, 32'h3FC00000, 3'b000, 32'h40400000,
           0,0,0,0,0, "1.5+1.5 ");
    // 1.0 + (-1.0) = 0.0
    run_op(32'h3F800000, 32'hBF800000, 3'b000, 32'h00000000,
           0,0,0,0,0, "1-1=0   ");
    // -1.5 + 1.0 = -0.5
    run_op(32'hBFC00000, 32'h3F800000, 3'b000, 32'hBF000000,
           0,0,0,0,0, "-1.5+1  ");

    $display("=== Testes de Subtracao ===");
    // 3.0 - 1.0 = 2.0
    run_op(32'h40400000, 32'h3F800000, 3'b001, 32'h40000000,
           0,0,0,0,0, "3-1=2   ");
    // 1.0 - 1.0 = 0.0
    run_op(32'h3F800000, 32'h3F800000, 3'b001, 32'h00000000,
           0,0,0,0,0, "1-1=0   ");

    $display("=== Testes de Multiplicacao ===");
    // 2.0 * 3.0 = 6.0
    run_op(32'h40000000, 32'h40400000, 3'b010, 32'h40C00000,
           0,0,0,0,0, "2*3=6   ");
    // 1.0 * 1.0 = 1.0
    run_op(32'h3F800000, 32'h3F800000, 3'b010, 32'h3F800000,
           0,0,0,0,0, "1*1=1   ");
    // -2.0 * 3.0 = -6.0
    run_op(32'hC0000000, 32'h40400000, 3'b010, 32'hC0C00000,
           0,0,0,0,0, "-2*3=-6 ");
    // 0.5 * 0.5 = 0.25
    run_op(32'h3F000000, 32'h3F000000, 3'b010, 32'h3E800000,
           0,0,0,0,0, ".5*.5   ");

    $display("=== Testes de Divisao ===");
    // 6.0 / 2.0 = 3.0
    run_op(32'h40C00000, 32'h40000000, 3'b011, 32'h40400000,
           0,0,0,0,0, "6/2=3   ");
    // 1.0 / 1.0 = 1.0
    run_op(32'h3F800000, 32'h3F800000, 3'b011, 32'h3F800000,
           0,0,0,0,0, "1/1=1   ");
    // 1.0 / 2.0 = 0.5
    run_op(32'h3F800000, 32'h40000000, 3'b011, 32'h3F000000,
           0,0,0,0,0, "1/2=0.5 ");

    $display("=== Testes de Igualdade ===");
    // 1.0 == 1.0 = true (1.0)
    run_op(32'h3F800000, 32'h3F800000, 3'b100, 32'h3F800000,
           0,0,0,0,0, "1==1    ");
    // 1.0 == 2.0 = false (0.0)
    run_op(32'h3F800000, 32'h40000000, 3'b100, 32'h00000000,
           0,0,0,0,0, "1==2    ");
    // +0 == -0 = true
    run_op(32'h00000000, 32'h80000000, 3'b100, 32'h3F800000,
           0,0,0,0,0, "+0==-0  ");

    $display("=== Testes de Menor Que ===");
    // 1.0 < 2.0 = true
    run_op(32'h3F800000, 32'h40000000, 3'b101, 32'h3F800000,
           0,0,0,0,0, "1<2=T   ");
    // 2.0 < 1.0 = false
    run_op(32'h40000000, 32'h3F800000, 3'b101, 32'h00000000,
           0,0,0,0,0, "2<1=F   ");
    // -1.0 < 1.0 = true
    run_op(32'hBF800000, 32'h3F800000, 3'b101, 32'h3F800000,
           0,0,0,0,0, "-1<1=T  ");
    // 1.0 < 1.0 = false
    run_op(32'h3F800000, 32'h3F800000, 3'b101, 32'h00000000,
           0,0,0,0,0, "1<1=F   ");

    $display("=== Testes de Casos Especiais ===");
    // NaN + x = NaN
    run_op(32'h7FC00000, 32'h3F800000, 3'b000, 32'h7FC00000,
           1,0,0,0,0, "NaN+x   ");
    // x / 0 = +Inf + flag div_zero
    run_op(32'h3F800000, 32'h00000000, 3'b011, 32'h7F800000,
           0,1,0,0,0, "1/0=Inf ");
    // Inf + Inf = Inf
    run_op(32'h7F800000, 32'h7F800000, 3'b000, 32'h7F800000,
           0,0,0,0,0, "Inf+Inf ");
    // Inf - Inf = NaN
    run_op(32'h7F800000, 32'h7F800000, 3'b001, 32'h7FC00000,
           1,0,0,0,0, "Inf-Inf ");
    // Inf * 0 = NaN
    run_op(32'h7F800000, 32'h00000000, 3'b010, 32'h7FC00000,
           1,0,0,0,0, "Inf*0   ");
    // NaN == NaN = false + inv_op
    run_op(32'h7FC00000, 32'h7FC00000, 3'b100, 32'h00000000,
           1,0,0,0,0, "NaN==N  ");

    $display("=== Resumo ===");
    $display("PASS: %0d   FAIL: %0d", pass_count, fail_count);

    $finish;
end

// Dump para visualizacao de formas de onda
initial begin
    $dumpfile("fpu_tb.vcd");
    $dumpvars(0, tb_fpu);
end

endmodule