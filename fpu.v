module fpu (
    input  wire        clock,
    input  wire        reset,
    input  wire        start,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  op, // 000:ADD, 001:SUB, 010:MUL, 011:DIV, 100:EQ, 101:SLT
    
    output wire [31:0] c,
    output wire        busy,
    output wire        done,
    output wire        f_inv_op,
    output wire        f_div_zero,
    output wire        f_overflow,
    output wire        f_underflow,
    output wire        f_inexact
);

    // unpacking dos operandos
    wire sign_a, sign_b;
    wire [7:0] exp_a, exp_b;
    wire [23:0] mant_a, mant_b;
    wire is_zero_a, is_zero_b, is_inf_a, is_inf_b, is_nan_a, is_nan_b, is_subnorm_a, is_subnorm_b;

    fpu_unpacker unp_a (
        .operand(a), .sign(sign_a), .exp(exp_a), .mant(mant_a),
        .is_zero(is_zero_a), .is_inf(is_inf_a), .is_nan(is_nan_a), .is_subnormal(is_subnorm_a)
    );

    fpu_unpacker unp_b (
        .operand(b), .sign(sign_b), .exp(exp_b), .mant(mant_b),
        .is_zero(is_zero_b), .is_inf(is_inf_b), .is_nan(is_nan_b), .is_subnormal(is_subnorm_b)
    );

    // ADD / SUB
    wire add_sign;
    wire [7:0] add_exp;
    wire [27:0] add_mant;
    fpu_add_sub adder (
        .sign_a(sign_a), .exp_a(exp_a), .mant_a(mant_a),
        .sign_b(sign_b), .exp_b(exp_b), .mant_b(mant_b),
        .op_sub(op[0]), // 0 para ADD, 1 para SUB
        .res_sign(add_sign), .res_exp(add_exp), .res_mant(add_mant)
    );

    // MUL
    wire mul_sign;
    wire [9:0] mul_exp;
    wire [27:0] mul_mant;
    wire mul_busy_out, mul_done_out;
    reg  mul_start_reg;

    fpu_mul multiplier (
        .clock(clock), .reset(reset), .start(mul_start_reg),
        .sign_a(sign_a), .exp_a(exp_a), .mant_a(mant_a),
        .sign_b(sign_b), .exp_b(exp_b), .mant_b(mant_b),
        .busy(mul_busy_out), .done(mul_done_out),
        .res_sign(mul_sign), .res_exp(mul_exp), .res_mant(mul_mant)
    );

    // DIV
    wire div_sign, div_f_div_zero;
    wire [9:0] div_exp;
    wire [27:0] div_mant;
    wire div_busy_out, div_done_out;
    reg  div_start_reg;

    fpu_div divider (
        .clock(clock), .reset(reset), .start(div_start_reg),
        .sign_a(sign_a), .exp_a(exp_a), .mant_a(mant_a),
        .sign_b(sign_b), .exp_b(exp_b), .mant_b(mant_b),
        .busy(div_busy_out), .done(div_done_out), .f_div_zero(div_f_div_zero),
        .res_sign(div_sign), .res_exp(div_exp), .res_mant(div_mant)
    );

    // CMP (EQ / SLT)
    wire [31:0] cmp_res;
    fpu_cmp comparator (
        .sign_a(sign_a), .exp_a(exp_a), .mant_a(mant_a), .is_zero_a(is_zero_a),
        .sign_b(sign_b), .exp_b(exp_b), .mant_b(mant_b), .is_zero_b(is_zero_b),
        .is_slt(op[0]), // 0 para EQ, 1 para SLT
        .res_cmp(cmp_res)
    );

    // mux normalizador
    reg        norm_sign_in;
    reg [9:0]  norm_exp_in;
    reg [27:0] norm_mant_in;

    always @(*) begin
        case(op)
            3'b000, 3'b001: begin
                norm_sign_in = add_sign;
                norm_exp_in  = {2'b00, add_exp};
                norm_mant_in = add_mant;
            end
            3'b010: begin
                norm_sign_in = mul_sign;
                norm_exp_in  = mul_exp;
                norm_mant_in = mul_mant;
            end
            3'b011: begin
                norm_sign_in = div_sign;
                norm_exp_in  = div_exp;
                norm_mant_in = div_mant;
            end
            default: begin
                norm_sign_in = 1'b0;
                norm_exp_in  = 10'd0;
                norm_mant_in = 28'd0;
            end
        endcase
    end

    wire        norm_sign_out, norm_overflow, norm_underflow, norm_inexact;
    wire [7:0]  norm_exp_out;
    wire [22:0] norm_frac_out;

    fpu_normalizer normalizer (
        .sign(norm_sign_in), .exp_in(norm_exp_in), .mant_in(norm_mant_in),
        .res_sign(norm_sign_out), .res_exp(norm_exp_out), .res_frac(norm_frac_out),
        .f_overflow(norm_overflow), .f_underflow(norm_underflow), .f_inexact(norm_inexact)
    );

    // operacoes invalidas
    wire is_inv_add = (op == 3'b000) && is_inf_a && is_inf_b && (sign_a != sign_b);
    wire is_inv_sub = (op == 3'b001) && is_inf_a && is_inf_b && (sign_a == sign_b);
    wire is_inv_mul = (op == 3'b010) && ((is_zero_a && is_inf_b) || (is_inf_a && is_zero_b));
    wire is_inv_div = (op == 3'b011) && ((is_zero_a && is_zero_b) || (is_inf_a && is_inf_b));
    wire flag_inv_op_comb = is_nan_a || is_nan_b || is_inv_add || is_inv_sub || is_inv_mul || is_inv_div;

    reg        spec_is_inf;
    reg        spec_is_zero;
    reg        spec_sign;

    always @(*) begin
        spec_is_inf  = 1'b0;
        spec_is_zero = 1'b0;
        spec_sign    = 1'b0;

        case (op)
            3'b000: begin
                if (is_inf_a) begin spec_is_inf = 1'b1; spec_sign = sign_a; end
                if (is_inf_b) begin spec_is_inf = 1'b1; spec_sign = sign_b; end
            end
            3'b001: begin
                if (is_inf_a) begin spec_is_inf = 1'b1; spec_sign = sign_a; end
                if (is_inf_b) begin spec_is_inf = 1'b1; spec_sign = ~sign_b; end
            end
            3'b010: begin
                if (is_inf_a || is_inf_b) begin spec_is_inf = 1'b1; spec_sign = sign_a ^ sign_b; end
            end
            3'b011: begin
                if (is_inf_a && !is_inf_b) begin spec_is_inf = 1'b1; spec_sign = sign_a ^ sign_b; end
                if (!is_inf_a && is_inf_b) begin spec_is_zero = 1'b1; spec_sign = sign_a ^ sign_b; end 
            end
            default: ;
        endcase
    end

    // fsm
    reg [1:0] state;
    localparam IDLE    = 2'd0;
    localparam COMPUTE = 2'd1;
    localparam FINISH  = 2'd2;

    reg [31:0] reg_c;
    reg reg_busy, reg_done;
    reg reg_f_inv_op, reg_f_div_zero, reg_f_overflow, reg_f_underflow, reg_f_inexact;

    assign c           = reg_c;
    assign busy        = reg_busy;
    assign done        = reg_done;
    assign f_inv_op    = reg_f_inv_op;
    assign f_div_zero  = reg_f_div_zero;
    assign f_overflow  = reg_f_overflow;
    assign f_underflow = reg_f_underflow;
    assign f_inexact   = reg_f_inexact;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state           <= IDLE;
            reg_busy        <= 1'b0;
            reg_done        <= 1'b0;
            div_start_reg   <= 1'b0;
            mul_start_reg   <= 1'b0;
            reg_c           <= 32'd0;
            reg_f_inv_op    <= 1'b0;
            reg_f_div_zero  <= 1'b0;
            reg_f_overflow  <= 1'b0;
            reg_f_underflow <= 1'b0;
            reg_f_inexact   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    reg_done <= 1'b0;
                    if (start) begin
                        reg_busy <= 1'b1;
                        if (op == 3'b011) begin
                            div_start_reg <= 1'b1;
                        end else if (op == 3'b010) begin
                            mul_start_reg <= 1'b1;
                        end
                        state <= COMPUTE;
                    end
                end

                COMPUTE: begin
                    div_start_reg <= 1'b0;
                    mul_start_reg <= 1'b0; 
                    
                    if (op == 3'b011) begin
                        if (div_done_out) state <= FINISH;
                    end else if (op == 3'b010) begin
                        if (mul_done_out) state <= FINISH;
                    end else begin
                        state <= FINISH; 
                    end
                end

                FINISH: begin
                    reg_busy <= 1'b0;
                    reg_done <= 1'b1;
                    
                    reg_f_inv_op   <= flag_inv_op_comb;
                    reg_f_div_zero <= (op == 3'b011) ? (is_zero_b && !is_zero_a && !is_inf_a && !is_nan_a) : 1'b0;
                    
                    if (op == 3'b100 || op == 3'b101) begin
                        reg_c           <= cmp_res;
                        reg_f_overflow  <= 1'b0;
                        reg_f_underflow <= 1'b0;
                        reg_f_inexact   <= 1'b0;
                    end else if (flag_inv_op_comb) begin
                        reg_c           <= 32'h7FC00000;
                        reg_f_overflow  <= 1'b0;
                        reg_f_underflow <= 1'b0;
                        reg_f_inexact   <= 1'b0;
                    end else if (op == 3'b011 && is_zero_b) begin
                        reg_c           <= {sign_a ^ sign_b, 8'hFF, 23'd0};
                        reg_f_overflow  <= 1'b0;
                        reg_f_underflow <= 1'b0;
                        reg_f_inexact   <= 1'b0;
                    end else if (spec_is_inf) begin
                        reg_c           <= {spec_sign, 8'hFF, 23'd0};
                        reg_f_overflow  <= 1'b0; 
                        reg_f_underflow <= 1'b0;
                        reg_f_inexact   <= 1'b0;
                    end else if (spec_is_zero) begin
                        reg_c           <= {spec_sign, 31'd0};
                        reg_f_overflow  <= 1'b0;
                        reg_f_underflow <= 1'b0;
                        reg_f_inexact   <= 1'b0;
                    end else begin
                        reg_c           <= {norm_sign_out, norm_exp_out, norm_frac_out};
                        reg_f_overflow  <= norm_overflow;
                        reg_f_underflow <= norm_underflow;
                        reg_f_inexact   <= norm_inexact;
                    end
                    
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule