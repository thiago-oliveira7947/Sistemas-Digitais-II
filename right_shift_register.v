module right_shift_register (
    input  wire        clock,
    input  wire        reset,
    input  wire        start,
    input  wire [27:0] data_in,
    output reg  [27:0] data_out,
    output wire        done        // Novo!
);

    reg [4:0] shift_count;
    reg busy;

    assign done = ~busy;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            data_out    <= 28'd0;
            shift_count <= 5'd0;
            busy        <= 1'b0;
        end else if (start) begin
            data_out    <= data_in;
            shift_count <= 5'd0;
            busy        <= 1'b1;
        end else if (busy && shift_count < 5'd28) begin
            data_out    <= {1'b0, data_out[27:1]};
            shift_count <= shift_count + 1;
        end else begin
            busy <= 1'b0;
        end
    end
endmodule