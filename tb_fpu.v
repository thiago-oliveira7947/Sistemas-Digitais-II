`timescale 1ns/1ps

module tb_fpu;

    // =========================================================
    // DUT ports
    // =========================================================
    reg        clock, reset, start;
    reg [31:0] a, b;
    reg [2:0]  op;
    wire [31:0] c;
    wire        busy, done;
    wire        f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact;

    fpu dut (
        .clock(clock), .reset(reset), .start(start),
        .a(a), .b(b), .op(op),
        .c(c), .busy(busy), .done(done),
        .f_inv_op(f_inv_op), .f_div_zero(f_div_zero),
        .f_overflow(f_overflow), .f_underflow(f_underflow),
        .f_inexact(f_inexact)
    );

    // =========================================================
    // Clock
    // =========================================================
    always #5 clock = ~clock;

    // =========================================================
    // Contadores de testes
    // =========================================================
    integer pass_cnt, fail_cnt, test_num;

    // =========================================================
    // Tarefa auxiliar: dispara operação e aguarda done
    // =========================================================
    task run_op;
        input [31:0] in_a;
        input [31:0] in_b;
        input [2:0]  in_op;
        begin
            @(negedge clock);
            a = in_a; b = in_b; op = in_op; start = 1;
            @(negedge clock);
            start = 0;
            // aguarda done (máximo 200 ciclos)
            begin : wait_done
                integer i;
                for (i = 0; i < 200; i = i + 1) begin
                    if (done) disable wait_done;
                    @(negedge clock);
                end
            end
            @(negedge clock); // pipeline settle
        end
    endtask

    // =========================================================
    // Tarefa de verificação
    // =========================================================
    task check;
        input [127:0] name;   // até 16 chars
        input [31:0]  exp_c;
        input         exp_inv, exp_divz, exp_ovf, exp_udf, exp_inx;
        begin
            test_num = test_num + 1;
            if (c          === exp_c   &&
                f_inv_op   === exp_inv &&
                f_div_zero === exp_divz &&
                f_overflow === exp_ovf &&
                f_underflow=== exp_udf &&
                f_inexact  === exp_inx) begin
                $display("PASS [%0d] %s  c=%h", test_num, name, c);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL [%0d] %s", test_num, name);
                $display("       c got=%h  exp=%h", c, exp_c);
                $display("       flags got: inv=%b divz=%b ovf=%b udf=%b inx=%b",
                         f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact);
                $display("       flags exp: inv=%b divz=%b ovf=%b udf=%b inx=%b",
                         exp_inv, exp_divz, exp_ovf, exp_udf, exp_inx);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // =========================================================
    // Constantes IEEE-754 úteis
    // =========================================================
    localparam POS_INF    = 32'h7F800000;
    localparam NEG_INF    = 32'hFF800000;
    localparam POS_ZERO   = 32'h00000000;
    localparam NEG_ZERO   = 32'h80000000;
    localparam QNAN       = 32'h7FC00000;
    localparam POS_ONE    = 32'h3F800000; // 1.0
    localparam NEG_ONE    = 32'hBF800000; // -1.0
    localparam POS_TWO    = 32'h40000000; // 2.0
    localparam NEG_TWO    = 32'hC0000000; // -2.0
    localparam POS_HALF   = 32'h3F000000; // 0.5
    localparam POS_THREE  = 32'h40400000; // 3.0
    localparam MAX_NORM   = 32'h7F7FFFFF; // maior normal
    localparam MIN_SUBNORM= 32'h00000001; // menor subnormal +
    localparam MIN_NORM   = 32'h00800000; // menor normal positivo
    localparam NEG_MIN_N  = 32'h80800000; // menor normal negativo

    // =========================================================
    // MAIN
    // =========================================================
    initial begin
        clock = 0; reset = 1; start = 0;
        a = 0; b = 0; op = 0;
        pass_cnt = 0; fail_cnt = 0; test_num = 0;

        repeat(4) @(negedge clock);
        reset = 0;
        @(negedge clock);

        // ==============================================
        // ====  ADD  (op = 3'b000)  ====================
        // ==============================================

        // 1) 1.0 + 1.0 = 2.0
        run_op(POS_ONE, POS_ONE, 3'b000);
        check("ADD 1+1=2       ", POS_TWO,  0,0,0,0,0);

        // 2) 1.0 + (-1.0) = 0.0
        run_op(POS_ONE, NEG_ONE, 3'b000);
        check("ADD 1+(-1)=0    ", POS_ZERO, 0,0,0,0,0);

        // 3) 1.0 + 2.0 = 3.0
        run_op(POS_ONE, POS_TWO, 3'b000);
        check("ADD 1+2=3       ", POS_THREE,0,0,0,0,0);

        // 4) 0.5 + 0.5 = 1.0
        run_op(POS_HALF, POS_HALF, 3'b000);
        check("ADD 0.5+0.5=1   ", POS_ONE,  0,0,0,0,0);

        // 5) +inf + +inf = +inf
        run_op(POS_INF, POS_INF, 3'b000);
        check("ADD +inf++inf   ", POS_INF,  0,0,0,0,0);

        // 6) +inf + (-inf) = NaN (inv_op)
        run_op(POS_INF, NEG_INF, 3'b000);
        check("ADD +inf+-inf=QN", QNAN,     1,0,0,0,0);

        // 7) NaN + 1.0 = NaN
        run_op(QNAN, POS_ONE, 3'b000);
        check("ADD NaN+1=NaN   ", QNAN,     1,0,0,0,0);

        // 8) 0 + 0 = 0
        run_op(POS_ZERO, POS_ZERO, 3'b000);
        check("ADD 0+0=0       ", POS_ZERO, 0,0,0,0,0);

        // 9) -1 + -1 = -2
        run_op(NEG_ONE, NEG_ONE, 3'b000);
        check("ADD -1+-1=-2    ", NEG_TWO,  0,0,0,0,0);

        // ==============================================
        // ====  SUB  (op = 3'b001)  ====================
        // ==============================================

        // 10) 2.0 - 1.0 = 1.0
        run_op(POS_TWO, POS_ONE, 3'b001);
        check("SUB 2-1=1       ", POS_ONE,  0,0,0,0,0);

        // 11) 1.0 - 1.0 = 0.0
        run_op(POS_ONE, POS_ONE, 3'b001);
        check("SUB 1-1=0       ", POS_ZERO, 0,0,0,0,0);

        // 12) 1.0 - 2.0 = -1.0
        run_op(POS_ONE, POS_TWO, 3'b001);
        check("SUB 1-2=-1      ", NEG_ONE,  0,0,0,0,0);

        // 13) +inf - (-inf) = +inf
        run_op(POS_INF, NEG_INF, 3'b001);
        check("SUB +inf--inf=+i", POS_INF,  0,0,0,0,0);

        // 14) +inf - +inf = NaN (inv_op)
        run_op(POS_INF, POS_INF, 3'b001);
        check("SUB +inf-+inf=QN", QNAN,     1,0,0,0,0);

        // 15) 0 - 1 = -1
        run_op(POS_ZERO, POS_ONE, 3'b001);
        check("SUB 0-1=-1      ", NEG_ONE,  0,0,0,0,0);

        // ==============================================
        // ====  MUL  (op = 3'b010)  ====================
        // ==============================================

        // 16) 1.0 * 1.0 = 1.0
        run_op(POS_ONE, POS_ONE, 3'b010);
        check("MUL 1*1=1       ", POS_ONE,  0,0,0,0,0);

        // 17) 2.0 * 3.0 = 6.0
        run_op(POS_TWO, POS_THREE, 3'b010);
        check("MUL 2*3=6       ", 32'h40C00000, 0,0,0,0,0);

        // 18) 1.0 * (-1.0) = -1.0
        run_op(POS_ONE, NEG_ONE, 3'b010);
        check("MUL 1*-1=-1     ", NEG_ONE,  0,0,0,0,0);

        // 19) (-1.0) * (-1.0) = 1.0
        run_op(NEG_ONE, NEG_ONE, 3'b010);
        check("MUL -1*-1=1     ", POS_ONE,  0,0,0,0,0);

        // 20) 0 * inf = NaN (inv_op)
        run_op(POS_ZERO, POS_INF, 3'b010);
        check("MUL 0*inf=NaN   ", QNAN,     1,0,0,0,0);

        // 21) inf * inf = +inf
        run_op(POS_INF, POS_INF, 3'b010);
        check("MUL inf*inf=+inf", POS_INF,  0,0,0,0,0);

        // 22) 0.5 * 2 = 1
        run_op(POS_HALF, POS_TWO, 3'b010);
        check("MUL 0.5*2=1     ", POS_ONE,  0,0,0,0,0);

        // 23) MAX_NORM * 2 = overflow
        run_op(MAX_NORM, POS_TWO, 3'b010);
        check("MUL MAX*2=+inf  ", POS_INF,  0,0,1,0,0);

        // ==============================================
        // ====  DIV  (op = 3'b011)  ====================
        // ==============================================

        // 24) 1.0 / 1.0 = 1.0
        run_op(POS_ONE, POS_ONE, 3'b011);
        check("DIV 1/1=1       ", POS_ONE,  0,0,0,0,0);

        // 25) 2.0 / 2.0 = 1.0
        run_op(POS_TWO, POS_TWO, 3'b011);
        check("DIV 2/2=1       ", POS_ONE,  0,0,0,0,0);

        // 26) 1.0 / 2.0 = 0.5
        run_op(POS_ONE, POS_TWO, 3'b011);
        check("DIV 1/2=0.5     ", POS_HALF, 0,0,0,0,0);

        // 27) 3.0 / 1.0 = 3.0
        run_op(POS_THREE, POS_ONE, 3'b011);
        check("DIV 3/1=3       ", POS_THREE,0,0,0,0,0);

        // 28) 1.0 / 0 = +inf (div_zero)
        run_op(POS_ONE, POS_ZERO, 3'b011);
        check("DIV 1/0=+inf    ", POS_INF,  0,1,0,0,0);

        // 29) -1.0 / 0 = -inf (div_zero)
        run_op(NEG_ONE, POS_ZERO, 3'b011);
        check("DIV -1/0=-inf   ", NEG_INF,  0,1,0,0,0);

        // 30) 0/0 = NaN (inv_op)
        run_op(POS_ZERO, POS_ZERO, 3'b011);
        check("DIV 0/0=NaN     ", QNAN,     1,0,0,0,0);

        // 31) inf / inf = NaN
        run_op(POS_INF, POS_INF, 3'b011);
        check("DIV inf/inf=NaN ", QNAN,     1,0,0,0,0);

        // 32) inf / 1 = +inf
        run_op(POS_INF, POS_ONE, 3'b011);
        check("DIV inf/1=+inf  ", POS_INF,  0,0,0,0,0);

        // 33) 1 / inf = 0 (ou subnormal)
        run_op(POS_ONE, POS_INF, 3'b011);
        check("DIV 1/inf=0     ", POS_ZERO, 0,0,0,0,0);  // udf=0, resultado exato

        // ==============================================
        // ====  EQ   (op = 3'b100)  ====================
        // ==============================================

        // 34) 1.0 == 1.0 → 1.0
        run_op(POS_ONE, POS_ONE, 3'b100);
        check("EQ 1==1=T       ", POS_ONE,  0,0,0,0,0);

        // 35) 1.0 == 2.0 → 0.0
        run_op(POS_ONE, POS_TWO, 3'b100);
        check("EQ 1==2=F       ", POS_ZERO, 0,0,0,0,0);

        // 36) 0 == -0 → true
        run_op(POS_ZERO, NEG_ZERO, 3'b100);
        check("EQ +0==-0=T     ", POS_ONE,  0,0,0,0,0);

        // 37) NaN == NaN → false (0)
        run_op(QNAN, QNAN, 3'b100);
        check("EQ NaN==NaN=F   ", POS_ZERO, 1,0,0,0,0);

        // ==============================================
        // ====  SLT  (op = 3'b101)  ====================
        // ==============================================

        // 38) 1.0 < 2.0 → true
        run_op(POS_ONE, POS_TWO, 3'b101);
        check("SLT 1<2=T       ", POS_ONE,  0,0,0,0,0);

        // 39) 2.0 < 1.0 → false
        run_op(POS_TWO, POS_ONE, 3'b101);
        check("SLT 2<1=F       ", POS_ZERO, 0,0,0,0,0);

        // 40) 1.0 < 1.0 → false
        run_op(POS_ONE, POS_ONE, 3'b101);
        check("SLT 1<1=F       ", POS_ZERO, 0,0,0,0,0);

        // 41) -2.0 < 1.0 → true
        run_op(NEG_TWO, POS_ONE, 3'b101);
        check("SLT -2<1=T      ", POS_ONE,  0,0,0,0,0);

        // 42) -1.0 < -2.0 → false
        run_op(NEG_ONE, NEG_TWO, 3'b101);
        check("SLT -1<-2=F     ", POS_ZERO, 0,0,0,0,0);

        // 43) NaN < 1.0 → false
        run_op(QNAN, POS_ONE, 3'b101);
        check("SLT NaN<1=F     ", POS_ZERO, 1,0,0,0,0);

        // ==============================================
        // ====  BORDA: Subnormais  =====================
        // ==============================================

        // 44) MIN_SUBNORM + 0 = MIN_SUBNORM
        run_op(MIN_SUBNORM, POS_ZERO, 3'b000);
        check("ADD minsubn+0   ", MIN_SUBNORM, 0,0,0,1,0);

        // 45) MIN_NORM - MIN_NORM = 0
        run_op(MIN_NORM, MIN_NORM, 3'b001);
        check("SUB minN-minN=0 ", POS_ZERO, 0,0,0,0,0);

        // ==============================================
        // ====  Reset no meio de MUL  ==================
        // ==============================================

        // 46) Inicia MUL, reseta antes de terminar, verifica estado limpo
        @(negedge clock);
        a = POS_TWO; b = POS_TWO; op = 3'b010; start = 1;
        @(negedge clock); start = 0;
        repeat(3) @(negedge clock);
        reset = 1;
        @(negedge clock);
        reset = 0;
        @(negedge clock);
        test_num = test_num + 1;
        if (busy === 0 && done === 0) begin
            $display("PASS [%0d] RESET-MID-MUL: busy=0 done=0", test_num);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL [%0d] RESET-MID-MUL: busy=%b done=%b", test_num, busy, done);
            fail_cnt = fail_cnt + 1;
        end

        // ==============================================
        // Resultado final
        // ==============================================
        $display("\n========================================");
        $display("  TOTAL: %0d tests | PASS: %0d | FAIL: %0d",
                 test_num, pass_cnt, fail_cnt);
        $display("========================================");
        $finish;
    end

    // Watchdog global
    initial begin
        #500000;
        $display("TIMEOUT: simulacao travou");
        $finish;
    end

endmodule