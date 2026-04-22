module barrel_shifter_right_51 (
    input  wire [50:0] data_in,
    input  wire [4:0]  shamt,   // Quantidade de deslocamento (0 a 31)
    output wire [50:0] data_out
);
    wire [50:0] s0, s1, s2, s3, s4;

    // Estágio 0: Desloca 1 bit se shamt[0] for 1
    assign s0 = shamt[0] ? {1'b0, data_in[50:1]} : data_in;

    // Estágio 1: Desloca 2 bits se shamt[1] for 1
    assign s1 = shamt[1] ? {2'b0, s0[50:2]} : s0;

    // Estágio 2: Desloca 4 bits se shamt[2] for 1
    assign s2 = shamt[2] ? {4'b0, s1[50:4]} : s1;

    // Estágio 3: Desloca 8 bits se shamt[3] for 1
    assign s3 = shamt[3] ? {8'b0, s2[50:8]} : s2;

    // Estágio 4: Desloca 16 bits se shamt[4] for 1
    assign s4 = shamt[4] ? {16'b0, s3[50:16]} : s3;

    assign data_out = s4;
endmodule