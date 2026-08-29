/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 4                                           */
/* Matrix-Vector Mult. (MVM) testbench             */
/***************************************************/

`timescale 1 ns / 1 ps

module mvm_tb();

// Define clock period to be used in simulation
localparam CLK_PERIOD = 4; 				 
// DUT parameters
localparam IWIDTH = 8;
localparam OWIDTH = 32;
localparam MEM_DATAW = IWIDTH * 8;
localparam VEC_DATAW = IWIDTH * 8;
localparam MAT_DATAW = IWIDTH * 8;
localparam NUM_OLANES = 8;
// Test parameters
localparam M = 128; // matrix height
localparam N = 128; // matrix width or vector length
localparam M_PADDED = $rtoi($ceil(1.0 * M / NUM_OLANES) * NUM_OLANES);
localparam N_PADDED = $rtoi($ceil(1.0 * N / 8) * 8);
localparam VEC_MEM_DEPTH = ((N_PADDED / 8) > 256)? N_PADDED / 8 : 256;
localparam VEC_ADDRW = $clog2(VEC_MEM_DEPTH);
localparam MAT_MEM_DEPTH = ((N_PADDED * M_PADDED / 8 / NUM_OLANES) > 512)? N_PADDED * M_PADDED / 8 / NUM_OLANES : 512;
localparam MAT_ADDRW = $clog2(MAT_MEM_DEPTH);

// Declare logic signals for the DUT's inputs and outputs
logic clk;
logic rst;
logic [VEC_DATAW-1:0] i_vec_wdata;
logic [VEC_ADDRW-1:0] i_vec_waddr;
logic i_vec_wen;
logic [MAT_DATAW-1:0] i_mat_wdata;
logic [MAT_ADDRW-1:0] i_mat_waddr;
logic [NUM_OLANES-1:0] i_mat_wen;
logic i_start;
logic [VEC_ADDRW-1:0] i_vec_start_addr;
logic [VEC_ADDRW:0] i_vec_num_words;
logic [MAT_ADDRW-1:0] i_mat_start_addr;
logic [MAT_ADDRW:0] i_mat_num_rows_per_olane;
logic [OWIDTH*NUM_OLANES-1:0] o_result;
logic o_busy;
logic o_valid;

// Instantiate the design under test (dut) and connect its input/output ports to the declared signals.
mvm # (
    .IWIDTH(IWIDTH),
    .OWIDTH(OWIDTH),
    .VEC_MEM_DEPTH(VEC_MEM_DEPTH),
    .MAT_MEM_DEPTH(MAT_MEM_DEPTH),
    .NUM_OLANES(NUM_OLANES)
) dut (
    .clk(clk),
    .rst(rst),
    .i_vec_wdata(i_vec_wdata),
    .i_vec_waddr(i_vec_waddr),
    .i_vec_wen(i_vec_wen),
    .i_mat_wdata(i_mat_wdata),
    .i_mat_waddr(i_mat_waddr),
    .i_mat_wen(i_mat_wen),
    .i_start(i_start),
    .i_vec_start_addr(i_vec_start_addr),
    .i_vec_num_words(i_vec_num_words),
    .i_mat_start_addr(i_mat_start_addr),
    .i_mat_num_rows_per_olane(i_mat_num_rows_per_olane),
    .o_busy(o_busy),
    .o_result(o_result),
    .o_valid(o_valid)
);

// Since the DUT tested here needs a clock signal, this initial block generates a clock signal with
// period 4ns and 50% duty cycle (i.e., 2ns high and 2ns low)
initial begin
    clk = 1'b0;
    // The forever keyword means this keeps happening until the end of time (wait for half a clock
    // period, and flip its state)
    forever #(CLK_PERIOD/2) clk = ~clk; 
end

logic signed [IWIDTH-1:0] test_vector [0:N_PADDED-1];
logic signed [IWIDTH-1:0] test_matrix [0:M_PADDED-1][0:N_PADDED-1];
logic signed [OWIDTH-1:0] golden_result [0:M_PADDED-1];
integer i, j;

// Initial block to generate test inputs and calculate their golden results
initial begin
    // Generate test vector and matrix
    for (i = 0; i < N_PADDED; i = i + 1) begin
        for (j = 0; j < M; j = j + 1) begin
            if (i < N) test_matrix[j][i] = $random;
            else test_matrix[j][i] = 0;
        end
        for (j = M; j < M_PADDED; j = j + 1) begin
            test_matrix[j][i] = 0;
        end
        
        if (i < N) test_vector[i] = $random;
        else test_vector[i] = 0;
    end
    
    // Calculate golden result
    for (j = 0; j < M_PADDED; j = j + 1) begin
        golden_result[j] = 0;
        for (i = 0; i < N_PADDED; i = i + 1) begin
            golden_result[j] = golden_result[j] + (test_vector[i] * test_matrix[j][i]);
        end
    end
end

integer row_id, word_id, element_id;

// Initial block to supply inputs to the ciruit under test
initial begin	
    rst = 1'b1;
    i_vec_wdata = 'd0;
    i_vec_waddr = 'd0;
    i_vec_wen = 1'b0;
    i_mat_wdata = 'd0;
    i_mat_waddr = 'd0;
    i_mat_wen = 'd0;
    i_start = 1'b0;
    i_vec_start_addr = 'd0;
    i_vec_num_words = 'd0;
    i_mat_start_addr = 'd0;
    i_mat_num_rows_per_olane = 'd0;
    #(50*CLK_PERIOD);
	rst = 1'b0;
	i_vec_start_addr = 0;
	i_mat_start_addr = 0;
    i_vec_num_words = N_PADDED / 8;
    i_mat_num_rows_per_olane = M_PADDED / NUM_OLANES;
    #(CLK_PERIOD);
    
    for (word_id = 0; word_id < N_PADDED/8; word_id = word_id + 1) begin
        for (element_id = 0; element_id < 8; element_id = element_id + 1) begin
            i_vec_wdata[element_id * IWIDTH +: IWIDTH] = test_vector[word_id * 8 + element_id];
        end
        i_vec_waddr = i_vec_start_addr + word_id;
        i_vec_wen = 1'b1;
        #(CLK_PERIOD);
    end
    i_vec_wen = 1'b0;
    #(CLK_PERIOD);
    
    for (row_id = 0; row_id < M_PADDED; row_id = row_id + 1) begin
        for (word_id = 0; word_id < N_PADDED/8; word_id = word_id + 1) begin
            for (element_id = 0; element_id < 8; element_id = element_id + 1) begin
                i_mat_wdata[element_id * IWIDTH +: IWIDTH] = test_matrix[row_id][word_id * 8 + element_id];
            end
            i_mat_waddr = i_mat_start_addr + (row_id/NUM_OLANES * N_PADDED/8) + word_id;
            i_mat_wen = 'd0;
            i_mat_wen[row_id % NUM_OLANES] = 1'b1;
            #(CLK_PERIOD);
        end
    end
    i_mat_wen = 'd0;
    #(CLK_PERIOD);
    
    i_start = 1'b1;
    #(CLK_PERIOD);
    
    i_start = 1'b0;
    #(CLK_PERIOD);
end

integer output_element_id, output_element_itr;
logic sim_failed;

initial begin
    // Set time display format to be in 10^-9 sec, with 2 decimal places, and add " ns" suffix
    $timeformat(-9, 2, " ns");
    
    output_element_id = 0;
    sim_failed = 1'b0;
    
    while (output_element_id < M_PADDED) begin
        if (o_valid) begin
            for (output_element_itr = output_element_id; output_element_itr < output_element_id + NUM_OLANES; output_element_itr = output_element_itr + 1) begin
                $display("[%d] Golden Result = %d, DUT Result = %d", output_element_itr, golden_result[output_element_itr], $signed(o_result[(output_element_itr - output_element_id)*OWIDTH+:OWIDTH]));  
                if (o_result[(output_element_itr - output_element_id)*OWIDTH+:OWIDTH] !== golden_result[output_element_itr]) begin
                    sim_failed = 1'b1;
                end
            end
            output_element_id = output_element_id + NUM_OLANES;
        end
        #(CLK_PERIOD);
    end
    if (sim_failed) begin
        $display("TEST FAILED!");
    end else begin
        $display("TEST PASSED!");
    end
    $stop;    
end


endmodule