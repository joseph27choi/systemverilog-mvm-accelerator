/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 4                                           */
/* MVM Control FSM                                 */
/***************************************************/

module ctrl # (
    parameter VEC_ADDRW = 8,
    parameter MAT_ADDRW = 9,
    parameter VEC_SIZEW = VEC_ADDRW + 1,
    parameter MAT_SIZEW = MAT_ADDRW + 1
    
)(
    input  clk,
    input  rst,
    input  start,
    input  [VEC_ADDRW-1:0] vec_start_addr,
    input  [VEC_SIZEW-1:0] vec_num_words,
    input  [MAT_ADDRW-1:0] mat_start_addr,
    input  [MAT_SIZEW-1:0] mat_num_rows_per_olane,
    output [VEC_ADDRW-1:0] vec_raddr,
    output [MAT_ADDRW-1:0] mat_raddr,
    output accum_first,
    output accum_last,
    output ovalid,
    output busy
);

/******* Your code starts here *******/

enum {IDLE, COMPUTE} state, next_state;

logic [VEC_ADDRW-1:0] r_vec_start_addr;
logic [VEC_SIZEW-1:0] r_vec_num_words;
logic [MAT_ADDRW-1:0] r_mat_start_addr;
logic [MAT_SIZEW-1:0] r_mat_num_rows_per_olane;

logic [VEC_ADDRW-1:0] r_vec_raddr, r_next_vec_raddr;
logic [MAT_ADDRW-1:0] r_mat_raddr, r_next_mat_raddr;
logic r_accum_first, r_next_accum_first;
logic r_accum_last, r_next_accum_last;
logic r_ovalid, r_next_ovalid;
logic r_busy, r_next_busy;

logic [VEC_SIZEW-1:0] v, next_v;
logic [MAT_SIZEW-1:0] m, next_m;


always_ff @(posedge clk) begin : blockName
    if (rst) begin
        r_vec_start_addr <= vec_start_addr;
        r_vec_num_words <= vec_num_words;
        r_mat_start_addr <= mat_start_addr;
        r_mat_num_rows_per_olane <= mat_num_rows_per_olane;


        r_vec_raddr <= '0;
        r_mat_raddr <= '0;
        r_accum_first <= 0;
        r_accum_last <= 0;
        r_busy <= 0;
        r_ovalid <= 0;

        v <= 0;
        m <= 0;

        state <= IDLE;
    end else begin
        if (state == IDLE) begin
            r_vec_start_addr <= vec_start_addr;
            r_vec_num_words <= vec_num_words;
            r_mat_start_addr <= mat_start_addr;
            r_mat_num_rows_per_olane <= mat_num_rows_per_olane;
        end

        r_vec_raddr <= r_next_vec_raddr;
        r_mat_raddr <= r_next_mat_raddr;
        r_accum_first <= r_next_accum_first;
        r_accum_last <= r_next_accum_last;
        r_busy <= r_next_busy;
        r_ovalid <= r_next_ovalid;

        v <= next_v;
        m <= next_m;

        state <= next_state;
    end
end

always_comb begin: counter_logic
    next_v = v;
    next_m = m;
    
    case (state)
        IDLE: begin
            /* next_state is IDLE */
            next_v = 0;
            next_m = 0;

            /* next_state is COMPUTE */
            if (start) begin
                next_v = (r_vec_num_words == 1) ? 0 : 1;
                next_m = (r_vec_num_words == 1) ? 1 : 0;
            end
        end 
        COMPUTE: begin
            next_v = (v < r_vec_num_words-1) ? v + 1 : 0;
            next_m = (v < r_vec_num_words-1) ? m : m + 1;
        end 
    endcase
end

always_comb begin: state_decoder
    next_state = state;
    
    case (state)
        IDLE: begin
            if (start == 1)
                next_state = COMPUTE;
        end
        COMPUTE: begin
            if (m == r_mat_num_rows_per_olane)
                next_state = IDLE;
        end
    endcase
end


always_comb begin: output_decoder
    case (state)
        IDLE: begin
            /* next_state is IDLE */
            r_next_vec_raddr = '0;
            r_next_mat_raddr = '0;
            r_next_accum_first = 0;
            r_next_accum_last = 0;
            r_next_busy = 0;
            r_next_ovalid = 0;

            /* next_state is COMPUTE */
            if (start) begin
                r_next_vec_raddr = vec_start_addr;
                r_next_mat_raddr = mat_start_addr;
                r_next_accum_first = 1;
                r_next_accum_last = (v == r_vec_num_words-1) ? 1 : 0;
                r_next_busy = 1;
                r_next_ovalid = 1;
            end
        end
        COMPUTE: begin
            /* next_state is COMPUTE */
            r_next_vec_raddr = r_vec_start_addr + (v);
            r_next_mat_raddr = r_mat_start_addr + (r_vec_num_words * m + v);
            r_next_accum_first = (v == 0) ? 1 : 0;
            r_next_accum_last = (v == r_vec_num_words-1) ? 1 : 0;
            r_next_busy = 1;
            r_next_ovalid = 1;

            /* next_state is IDLE */
            if (m == r_mat_num_rows_per_olane) begin
                r_next_vec_raddr = '0;
                r_next_mat_raddr = '0;
                r_next_accum_first = 0;
                r_next_accum_last = 0;
                r_next_busy = 0;
                r_next_ovalid = 0;
            end
        end
    endcase
end

assign vec_raddr = r_vec_raddr;
assign mat_raddr = r_mat_raddr;
assign accum_first = r_accum_first;
assign accum_last = r_accum_last;
assign ovalid = r_ovalid;
assign busy = r_busy;


/******* Your code ends here ********/

endmodule
