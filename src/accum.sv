/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 4                                           */
/* Accumulator Module                              */
/***************************************************/

module accum # (
    parameter DATAW = 32,
    parameter ACCUMW = 32
)(
    input  clk,
    input  rst,
    input signed [DATAW-1:0] data,
    input ivalid,
    input first,
    input last,
    output signed [ACCUMW-1:0] result,
    output logic ovalid
);

/******* Your code starts here *******/

logic signed [ACCUMW-1:0] r_running_sum;

always_ff @(posedge clk) begin: running_sum_calculator
    if (rst) begin
        r_running_sum <= 0;
    end else begin
        priority if (!ivalid) begin
            r_running_sum <= r_running_sum;
        end else if (first) begin
            r_running_sum <= data;
        end else begin
            r_running_sum <= r_running_sum + $signed(data);
        end
    end
end

assign result = r_running_sum;

always_ff @(posedge clk) begin: validity_assertion
    if (rst) begin
        ovalid <= 0;
    end else begin
        ovalid <= last ? 1 : 0; 
    end
end

/******* Your code ends here ********/

endmodule