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
