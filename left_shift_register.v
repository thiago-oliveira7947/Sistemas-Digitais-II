module left_shift_register (
    input  wire        clock,
    input  wire        reset,
    input  wire        start,
    input  wire [27:0] data_in,
    output reg  [27:0] data_out,
    output wire        done
);

    reg [4:0] shift_count;
    reg busy;
    reg start_prev;  // Novo: detectar edge de start

    assign done = ~busy;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            data_out    <= 28'd0;
            shift_count <= 5'd0;
            busy        <= 1'b0;
            start_prev  <= 1'b0;
        end else begin
            // Detecta transição 0→1 de start
            if (start && !start_prev && !busy) begin
                data_out    <= data_in;
                shift_count <= 5'd0;
                busy        <= 1'b1;
            end else if (busy && shift_count < 5'd28) begin
                data_out    <= {data_out[26:0], 1'b0};
                shift_count <= shift_count + 1;
            end else if (shift_count >= 5'd28) begin
                busy <= 1'b0;
            end
            start_prev <= start;
        end
    end

endmodule