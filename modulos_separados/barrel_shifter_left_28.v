module barrel_shifter_left_28 (
    input  wire [27:0] data_in,
    input  wire [4:0]  shamt,
    output wire [27:0] data_out
);
    wire [27:0] s0, s1, s2, s3, s4;

    assign s0 = shamt[0] ? {data_in[26:0], 1'b0} : data_in;
    assign s1 = shamt[1] ? {s0[25:0], 2'b0}      : s0;
    assign s2 = shamt[2] ? {s1[23:0], 4'b0}      : s1;
    assign s3 = shamt[3] ? {s2[19:0], 8'b0}      : s2;
    assign s4 = shamt[4] ? {s3[11:0], 16'b0}     : s3;

    assign data_out = s4;
endmodule