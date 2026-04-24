`timescale 1ns / 1ps

module fpu_tb;

    reg clock;
    reg reset;
    reg start;
    reg [31:0] a, b;
    reg [2:0]  op;

    wire [31:0] c;
    wire busy, done;
    wire f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact;

    fpu uut (
        .clock(clock), .reset(reset), .start(start),
        .a(a), .b(b), .op(op),
        .c(c), .busy(busy), .done(done),
        .f_inv_op(f_inv_op), .f_div_zero(f_div_zero),
        .f_overflow(f_overflow), .f_underflow(f_underflow), .f_inexact(f_inexact)
    );

    always #5 clock = ~clock;

    integer cycles;

    task run_test;
        input [31:0] val_a, val_b;
        input [2:0]  val_op;
        input [31:0] expected_c;
        input        check_c;
        input [100*8:1] name;
    begin
        a = val_a;
        b = val_b;
        op = val_op;

        @(posedge clock);
        start = 1;
        @(posedge clock);
        start = 0;

        cycles = 0;
        while (done !== 1 && cycles < 120) begin
            @(posedge clock);
            cycles = cycles + 1;
        end

        if (cycles >= 100)
            $display("TIMEOUT (>100 ciclos) -> %s", name);

        if (check_c && c !== expected_c)
            $display("ERRO RESULTADO -> %s | esperado=%h obtido=%h", name, expected_c, c);

        $display("[%s] C=%h | Inv:%b Div0:%b OVF:%b UNF:%b Inex:%b",
            name, c, f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact);

        @(posedge clock);
    end
    endtask

    initial begin
        $dumpfile("fpu.vcd");
        $dumpvars(0, fpu_tb);

        clock = 0; reset = 1; start = 0;
        #20; reset = 0; #20;

        // ---------- BÁSICOS ----------
        run_test(32'h3F800000,32'h40000000,3'b000,32'h40400000,1,"1+2=3");
        run_test(32'h40000000,32'h3F800000,3'b001,32'h3F800000,1,"2-1=1");
        run_test(32'h40000000,32'h40000000,3'b010,32'h40800000,1,"2*2=4");
        run_test(32'h40800000,32'h40000000,3'b011,32'h40000000,1,"4/2=2");

        // ---------- ZERO ----------
        run_test(32'h00000000,32'h00000000,3'b000,32'h00000000,1,"0+0");
        run_test(32'h80000000,32'h00000000,3'b100,32'h3F800000,1,"-0==+0");

        // ---------- NaN ----------
        run_test(32'h7FC00000,32'h3F800000,3'b000,32'h7FC00000,1,"NaN+1");
        run_test(32'h7FC00000,32'h7FC00000,3'b100,32'h00000000,1,"NaN==NaN");

        // ---------- INF ----------
        run_test(32'h7F800000,32'h3F800000,3'b000,32'h7F800000,1,"Inf+1");
        run_test(32'h7F800000,32'hFF800000,3'b001,32'h7FC00000,0,"Inf-Inf");

        // ---------- DIV0 ----------
        run_test(32'h3F800000,32'h00000000,3'b011,32'h7F800000,0,"1/0");

        // ---------- OVERFLOW ----------
        run_test(32'h7F7FFFFF,32'h40000000,3'b010,32'h7F800000,0,"overflow mul");

        // ---------- UNDERFLOW ----------
        run_test(32'h00800000,32'h40000000,3'b011,32'h00000000,0,"underflow");

        // ---------- SUBNORMAL ----------
        run_test(32'h00000001,32'h00000001,3'b000,32'h00000002,0,"subnormal add");

        // ---------- ROUNDING ----------
        run_test(32'h3F800000,32'h40400000,3'b011,32'h3EAAAAAB,1,"1/3");
        run_test(32'h3F800000,32'h41200000,3'b011,32'h3DCCCCCD,1,"1/10");

        // ---------- SINAIS ----------
        run_test(32'hBF800000,32'h40000000,3'b010,32'hC0000000,1,"-1*2");
        run_test(32'hC0800000,32'hC0000000,3'b011,32'h40000000,1,"-4/-2");

        // ---------- COMPARAÇÃO ----------
        run_test(32'h3F800000,32'h3F800000,3'b100,32'h3F800000,1,"1==1");
        run_test(32'h3F800000,32'h40000000,3'b101,32'h3F800000,1,"1<2");
        run_test(32'h7FC00000,32'h3F800000,3'b101,32'h00000000,1,"NaN<1");

        $display("FIM");
        $finish;
    end

endmodule