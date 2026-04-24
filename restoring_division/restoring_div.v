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
