module uc #(
    parameter N = 24
)(
    input wire clk,
    input wire rst,
    input wire start,

    output reg load_m,
    output reg load_aq,
    output reg shift_aq,
    output reg update_a,
    output wire done
);

    localparam IDLE   = 3'b000,
               LOAD   = 3'b001,
               SHIFT  = 3'b010,
               UPDATE = 3'b011,
               DONE_S = 3'b100;

    // state (3 bits) stored in register.v instance
    wire [2:0] state;
    reg  [2:0] next_state;

    // iteration counter (N bits) stored in register.v instance
    wire [N-1:0] count;
    reg  [N-1:0] count_next;
    wire count_load;

    // combinational next-state / outputs logic (uses registered 'state' and 'count')
    always @(*) begin
        // default outputs
        load_m   = 1'b0;
        load_aq  = 1'b0;
        shift_aq = 1'b0;
        update_a = 1'b0;

        // default next values
        next_state = state;
        count_next = count;

        case (state)
            IDLE: begin
                if (start) begin
                    next_state = LOAD;
                end
            end

            // LOAD: capture divisor (M) and dividend into AQ, initialize counter
            LOAD: begin
                load_m  = 1'b1;
                load_aq = 1'b1;
                // prepare to perform first shift
                next_state = SHIFT;
                // set count to N (will be decremented in UPDATE)
                count_next = N;
            end

            // SHIFT: perform {A,Q} <- {A,Q} << 1
            SHIFT: begin
                shift_aq = 1'b1;
                // after shift, perform subtraction/update
                next_state = UPDATE;
            end

            // UPDATE: perform A <- A - M ; set Q0 depending on sign ; decrement counter
            UPDATE: begin
                update_a = 1'b1;
                // decrement iteration counter
                count_next = count - 1;
                // if more iterations remain, go back to SHIFT, else finish
                if (count > 1)
                    next_state = SHIFT;
                else
                    next_state = DONE_S;
            end

            // DONE: final state, return to IDLE (could also hold until reset/start low)
            DONE_S: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // load counter on LOAD (to initialize) and on UPDATE (to write decremented value)
    assign count_load = (state == LOAD) | (state == UPDATE);
    assign done = (state == DONE_S);

    // instantiate register for state (3 bits) -- always load next_state
    register #(.N(3)) state_reg (
        .clk(clk),
        .rst(rst),
        .load(1'b1),
        .data_in(next_state),
        .data_out(state)
    );

    // instantiate register for count (N bits)
    register #(.N(N)) count_reg (
        .clk(clk),
        .rst(rst),
        .load(count_load),
        .data_in(count_next),
        .data_out(count)
    );

endmodule
