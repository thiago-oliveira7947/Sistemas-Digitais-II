module fpu_div (
    input  wire        clock,
    input  wire        reset,
    input  wire        start,
    input  wire        sign_a,
    input  wire [7:0]  exp_a,
    input  wire [23:0] mant_a,
    input  wire        sign_b,
    input  wire [7:0]  exp_b,
    input  wire [23:0] mant_b,
    output reg         busy,
    output reg         done,
    output wire        f_div_zero,
    output wire        res_sign,
    output wire [9:0]  res_exp,
    output wire [27:0] res_mant 
);
    assign res_sign   = sign_a ^ sign_b;
    assign f_div_zero = (mant_b == 24'd0) && (exp_b == 8'd0);

    wire [9:0] exp_a_ext = {2'b00, exp_a};
    wire [9:0] exp_b_ext = {2'b00, exp_b};
    assign res_exp = exp_a_ext - exp_b_ext + 10'd127;

    reg [24:0] acc;
    reg [25:0] quociente;
    reg [24:0] divisor_reg;
    reg [4:0]  count;
    reg        sticky_bit_reg;
    
    reg [2:0]  state;
    localparam IDLE     = 3'd0;
    localparam SUBTRACT = 3'd1;
    localparam RESTORE  = 3'd2;
    localparam SHIFT    = 3'd3;
    localparam CLEANUP  = 3'd4;
    localparam FIM      = 3'd5;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state          <= IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;
            count          <= 5'd0;
            acc            <= 25'd0;
            quociente      <= 26'd0;
            divisor_reg    <= 25'd0;
            sticky_bit_reg <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start && !f_div_zero) begin
                        busy           <= 1'b1;
                        acc            <= {1'b0, mant_a}; 
                        quociente      <= 26'd0;
                        divisor_reg    <= {1'b0, mant_b};
                        count          <= 5'd26;
                        sticky_bit_reg <= 1'b0;
                        state          <= SUBTRACT;
                    end else if (start && f_div_zero) begin
                        done <= 1'b1;
                    end
                end

                SUBTRACT: begin
                    acc   <= acc - divisor_reg;
                    state <= RESTORE;
                end

                RESTORE: begin
                    if (acc[24] == 1'b1) begin
                        acc       <= acc + divisor_reg;
                        quociente <= {quociente[24:0], 1'b0};
                    end else begin
                        quociente <= {quociente[24:0], 1'b1};
                    end

                    // O 'end' que estava aqui em cima foi removido.
                    if (count == 5'd1) begin
                        state <= CLEANUP; 
                    end else begin
                        count <= count - 1;
                        state <= SHIFT;
                    end
                end // <- O 'end' correto do RESTORE é aqui.

                SHIFT: begin
                    acc   <= {acc[23:0], 1'b0};
                    state <= SUBTRACT;
                end

                CLEANUP: begin
                    sticky_bit_reg <= (acc != 25'd0);
                    state <= FIM;
                end

                FIM: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    assign res_mant = {2'b00, quociente[25:2], quociente[1], quociente[0], sticky_bit_reg};

endmodule