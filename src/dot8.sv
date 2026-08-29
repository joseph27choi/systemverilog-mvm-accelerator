/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 4                                           */
/* 8-Lane Dot Product Module                       */
/***************************************************/

module dot8 # (
    parameter IWIDTH = 8,
    parameter OWIDTH = 32
)(
    input clk,
    input rst,
    input signed [8*IWIDTH-1:0] vec0,
    input signed [8*IWIDTH-1:0] vec1,
    input ivalid,
    output signed [OWIDTH-1:0] result,
    output ovalid
);

/******* Your code starts here *******/
logic signed [8*IWIDTH-1:0] r_vec0;
logic signed [8*IWIDTH-1:0] r_vec1;
logic signed [2*IWIDTH-1:0] r_after_mult [0:7];
logic signed [2*IWIDTH:0] r_first_add [0:3];
logic signed [2*IWIDTH+1:0] r_second_add [0:1];
logic signed [2*IWIDTH+2:0] r_third_add;

logic r_valid[0:4];

always_ff @ (posedge clk) begin
    if (rst) begin
        r_vec0 <= 0;
        r_vec1 <= 0;
        r_after_mult[0] <= 0; r_after_mult[1] <= 0; r_after_mult[2] <= 0; r_after_mult[3] <= 0;
        r_after_mult[4] <= 0; r_after_mult[5] <= 0; r_after_mult[6] <= 0; r_after_mult[7] <= 0;
        r_first_add[0] <= 0; r_first_add[1] <= 0; r_first_add[2] <= 0; r_first_add[3] <= 0;
        r_second_add[0] <= 0; r_second_add[1] <= 0;
        r_valid[0] <= 0; r_valid[1] <= 0; r_valid[2] <= 0; r_valid[3] <= 0; r_valid[4] <= 0;
    end else begin
        r_vec0 <= vec0;
        r_vec1 <= vec1;
        r_valid[0] <= ivalid;
        
        // Multiplication
        r_after_mult[0] <= $signed(r_vec0[1*IWIDTH-1:0*IWIDTH]) * $signed(r_vec1[1*IWIDTH-1:0*IWIDTH]);
        r_after_mult[1] <= $signed(r_vec0[2*IWIDTH-1:1*IWIDTH]) * $signed(r_vec1[2*IWIDTH-1:1*IWIDTH]);
        r_after_mult[2] <= $signed(r_vec0[3*IWIDTH-1:2*IWIDTH]) * $signed(r_vec1[3*IWIDTH-1:2*IWIDTH]);
        r_after_mult[3] <= $signed(r_vec0[4*IWIDTH-1:3*IWIDTH]) * $signed(r_vec1[4*IWIDTH-1:3*IWIDTH]);
        r_after_mult[4] <= $signed(r_vec0[5*IWIDTH-1:4*IWIDTH]) * $signed(r_vec1[5*IWIDTH-1:4*IWIDTH]);
        r_after_mult[5] <= $signed(r_vec0[6*IWIDTH-1:5*IWIDTH]) * $signed(r_vec1[6*IWIDTH-1:5*IWIDTH]);
        r_after_mult[6] <= $signed(r_vec0[7*IWIDTH-1:6*IWIDTH]) * $signed(r_vec1[7*IWIDTH-1:6*IWIDTH]);
        r_after_mult[7] <= $signed(r_vec0[8*IWIDTH-1:7*IWIDTH]) * $signed(r_vec1[8*IWIDTH-1:7*IWIDTH]);
        r_valid[1] <= r_valid[0];
        
        // First add
        r_first_add[0] <= r_after_mult[0] + r_after_mult[1];
        r_first_add[1] <= r_after_mult[2] + r_after_mult[3];
        r_first_add[2] <= r_after_mult[4] + r_after_mult[5];
        r_first_add[3] <= r_after_mult[6] + r_after_mult[7];
        r_valid[2] <= r_valid[1];
        
        // Second add
        r_second_add[0] <= r_first_add[0] + r_first_add[1];
        r_second_add[1] <= r_first_add[2] + r_first_add[3];
        r_valid[3] <= r_valid[2];
        
        // Last add
        r_third_add <= r_second_add[0] + r_second_add[1];
        r_valid[4] <= r_valid[3];
    end
end 

assign result = r_third_add;
assign ovalid = r_valid[4];

/******* Your code ends here ********/

endmodule