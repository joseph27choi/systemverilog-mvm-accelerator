/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 4                                           */
/* Matrix Vector Multiplication (MVM) Module       */
/***************************************************/

module mvm # (
    parameter IWIDTH = 8,
    parameter OWIDTH = 32,
    parameter MEM_DATAW = IWIDTH * 8,
    parameter VEC_MEM_DEPTH = 256,
    parameter VEC_ADDRW = $clog2(VEC_MEM_DEPTH),
    parameter MAT_MEM_DEPTH = 512,
    parameter MAT_ADDRW = $clog2(MAT_MEM_DEPTH),
    parameter NUM_OLANES = 8
)(
    input clk,
    input rst,
    input [MEM_DATAW-1:0] i_vec_wdata,
    input [VEC_ADDRW-1:0] i_vec_waddr,
    input i_vec_wen,
    input [MEM_DATAW-1:0] i_mat_wdata,
    input [MAT_ADDRW-1:0] i_mat_waddr,
    input [NUM_OLANES-1:0] i_mat_wen,
    input i_start,
    input [VEC_ADDRW-1:0] i_vec_start_addr,
    input [VEC_ADDRW:0] i_vec_num_words,
    input [MAT_ADDRW-1:0] i_mat_start_addr,
    input [MAT_ADDRW:0] i_mat_num_rows_per_olane,
    output o_busy,
    output [OWIDTH*NUM_OLANES-1:0] o_result,
    output o_valid
);

/******* Your code starts here *******/
logic [MEM_DATAW-1:0] vec0;
logic [MEM_DATAW-1:0] vec1 [0:NUM_OLANES-1];
logic [MAT_ADDRW-1:0] mat_raddr;                // Connect to FSM
logic [VEC_ADDRW-1:0] vec_raddr;                // Connect to FSM
logic dot_valid;                                // Connect to FSM
logic first;                                    // Connect to FSM
logic last;                                     // Connect to FSM
logic [OWIDTH-1:0] result [0:NUM_OLANES-1];
logic ovalid [0:NUM_OLANES-1];
logic [OWIDTH-1:0] o_result_parts [0:NUM_OLANES-1];
logic o_valid_from_each_olane [0:NUM_OLANES-1];

// ---------------------------------------------------------------------------
// Pipeline alignment
// ---------------------------------------------------------------------------
// The control FSM emits {vec/mat raddr, dot_valid, first, last} in the same
// cycle. The operands, however, only appear one cycle later (synchronous
// memory read), and the dot product result appears another 5 cycles after
// that (dot8 pipeline depth). To keep the accumulator's control aligned with
// the data actually arriving at its inputs we must delay:
//   - dot_valid by MEM_LATENCY so it lines up with the operands at dot8's input
//   - first/last by MEM_LATENCY + DOT8_LATENCY so they line up with the dot8
//     result reaching the accumulator.
localparam MEM_LATENCY  = 1;                       // synchronous memory read
localparam DOT8_LATENCY = 5;                       // dot8 pipeline depth
localparam CTRL2ACC_LAT = MEM_LATENCY + DOT8_LATENCY;

logic dot_valid_d;                                 // dot_valid aligned to dot8 input
logic [CTRL2ACC_LAT-1:0] first_pipe;               // first aligned to accum input
logic [CTRL2ACC_LAT-1:0] last_pipe;                // last  aligned to accum input

always_ff @(posedge clk) begin
    if (rst) begin
        dot_valid_d <= 1'b0;
        first_pipe  <= '0;
        last_pipe   <= '0;
    end else begin
        dot_valid_d <= dot_valid;
        first_pipe  <= {first_pipe[CTRL2ACC_LAT-2:0], first};
        last_pipe   <= {last_pipe[CTRL2ACC_LAT-2:0], last};
    end
end

genvar i;
generate
for (i = 0; i < NUM_OLANES; i = i + 1) begin
    mem # (
        .DATAW(MEM_DATAW), .DEPTH(MAT_MEM_DEPTH), .ADDRW(MAT_ADDRW)
    ) matrix_mem (
        .clk(clk), .wdata(i_mat_wdata), .waddr(i_mat_waddr), .wen(i_mat_wen[i]), .raddr(mat_raddr), .rdata(vec1[i])
    );
    
    dot8 # (
        .IWIDTH(IWIDTH), .OWIDTH(OWIDTH)
   ) dot8_inst (
        .clk(clk), .rst(rst), .vec0(vec0), .vec1(vec1[i]), .ivalid(dot_valid_d), .result(result[i]), .ovalid(ovalid[i])
   );
   
    accum # (
        .DATAW(OWIDTH), .ACCUMW(OWIDTH)
   ) accum_inst (
        .clk(clk), .rst(rst), .data(result[i]), .ivalid(ovalid[i]), .first(first_pipe[CTRL2ACC_LAT-1]), .last(last_pipe[CTRL2ACC_LAT-1]), .result(o_result_parts[i]), .ovalid(o_valid_from_each_olane[i])
   );
end
endgenerate

ctrl # (
    .VEC_ADDRW(VEC_ADDRW), .MAT_ADDRW(MAT_ADDRW)  
) ctrl_inst (
    .clk(clk), .rst(rst), .start(i_start), .vec_start_addr(i_vec_start_addr), .vec_num_words(i_vec_num_words),
    .mat_start_addr(i_mat_start_addr),.mat_num_rows_per_olane(i_mat_num_rows_per_olane), .vec_raddr(vec_raddr), 
    .mat_raddr(mat_raddr), .accum_first(first), .accum_last(last), .ovalid(dot_valid), .busy(o_busy)
);

mem # (
    .DATAW(MEM_DATAW), .DEPTH(VEC_MEM_DEPTH), .ADDRW(VEC_ADDRW)
) vector_mem (
    .clk(clk), .wdata(i_vec_wdata), .waddr(i_vec_waddr), .wen(i_vec_wen), .raddr(vec_raddr), .rdata(vec0)
);

assign o_valid = o_valid_from_each_olane[0];

genvar j;
generate
    for (j = 0; j < NUM_OLANES; j = j + 1) begin : gen_lanes
        assign o_result[(j*OWIDTH) +: OWIDTH] = o_result_parts[j];
    end
endgenerate

/******* Your code ends here ********/

endmodule
