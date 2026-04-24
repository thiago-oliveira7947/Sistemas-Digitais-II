// Módulo de deslocamento para a direita de 28 bits (Puramente Combinacional)
module barrel_shifter_right_28 (
    input  wire [27:0] data_in,
    input  wire [4:0]  shamt,   // Quantidade de deslocamento (0 a 31)
    output wire [27:0] data_out
);
    wire [27:0] s0, s1, s2, s3, s4;

    assign s0 = shamt[0] ? {1'b0, data_in[27:1]} : data_in;
    assign s1 = shamt[1] ? {2'b0, s0[27:2]}      : s0;
    assign s2 = shamt[2] ? {4'b0, s1[27:4]}      : s1;
    assign s3 = shamt[3] ? {8'b0, s2[27:8]}      : s2;
    assign s4 = shamt[4] ? {16'b0, s3[27:16]}    : s3;

    assign data_out = s4;
endmodule