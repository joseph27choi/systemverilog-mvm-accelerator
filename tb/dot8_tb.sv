// ============================================================================
// dot8_tb.sv
//
// Self-checking, latency-agnostic testbench for the 8-lane fully-pipelined
// signed dot-product unit `dot8`.
//
// DUT interface (from the specification):
//   input  clk                       : clock
//   input  rst                       : active-high synchronous reset
//   input  [8*IWIDTH-1:0] vec0       : packed signed elements of vector 0
//   input  [8*IWIDTH-1:0] vec1       : packed signed elements of vector 1
//   input  ivalid                    : vec0/vec1 are valid this cycle
//   output signed [OWIDTH-1:0] result: signed scalar dot product
//   output ovalid                    : `result` is valid this cycle
//
// Strategy:
//   The DUT is fully pipelined, so its latency (number of cycles between an
//   `ivalid` input and the corresponding `ovalid` output) is fixed but is an
//   implementation detail. Instead of hard-coding that latency, this bench uses
//   a FIFO scoreboard:
//     * every cycle `ivalid` is high we push the golden-model result;
//     * every cycle `ovalid` is high we pop and compare.
//   This works for any pipeline depth and also verifies that the DUT produces
//   exactly one output per input (no dropped or duplicated results).
// ============================================================================

`timescale 1ns/1ps

module dot8_tb;

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------
  localparam int N      = 8;                     // number of lanes (fixed for dot8)
  localparam int IWIDTH = 8;                      // signed width of each input element
  // Width chosen so the accumulation can never overflow:
  //   max |product| = 2^(2*IWIDTH-2), summed over N lanes needs
  //   2*IWIDTH + clog2(N) bits including sign.
  localparam int OWIDTH = 2*IWIDTH + $clog2(N);

  // ---------------------------------------------------------------------------
  // DUT connections
  // ---------------------------------------------------------------------------
  logic                     clk;
  logic                     rst;
  logic [N*IWIDTH-1:0]      vec0;
  logic [N*IWIDTH-1:0]      vec1;
  logic                     ivalid;
  logic signed [OWIDTH-1:0] result;
  logic                     ovalid;

  dot8 #(
    .IWIDTH (IWIDTH),
    .OWIDTH (OWIDTH)
  ) dut (
    .clk    (clk),
    .rst    (rst),
    .vec0   (vec0),
    .vec1   (vec1),
    .ivalid (ivalid),
    .result (result),
    .ovalid (ovalid)
  );

  // ---------------------------------------------------------------------------
  // Clock: 10 ns period. Stimulus is driven on the negedge so inputs are stable
  // at the posedge that both the DUT and the monitors sample.
  // ---------------------------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Golden reference model
  // ---------------------------------------------------------------------------
  function automatic longint signed golden_dot(input logic [N*IWIDTH-1:0] a,
                                                input logic [N*IWIDTH-1:0] b);
    int i;
    logic signed [IWIDTH-1:0] ea, eb;
    longint signed acc;
    begin
      acc = 0;
      for (i = 0; i < N; i++) begin
        ea  = a[i*IWIDTH +: IWIDTH];   // reinterpret slice as signed
        eb  = b[i*IWIDTH +: IWIDTH];
        acc = acc + (ea * eb);
      end
      golden_dot = acc;
    end
  endfunction

  // Pack 8 signed lane values into the DUT input word (lane 0 in the LSBs).
  function automatic logic [N*IWIDTH-1:0] pack8(
      input logic signed [IWIDTH-1:0] e0, e1, e2, e3, e4, e5, e6, e7);
    begin
      pack8 = { e7, e6, e5, e4, e3, e2, e1, e0 };
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Scoreboard (array-based FIFO of expected results)
  // ---------------------------------------------------------------------------
  localparam int FIFO_DEPTH = 4096;
  longint signed exp_fifo [0:FIFO_DEPTH-1];
  int wr_ptr = 0;
  int rd_ptr = 0;

  int ivalid_count = 0;
  int ovalid_count = 0;
  int error_count  = 0;

  longint signed exp_val;

  // Push expected result for every valid input.
  always @(posedge clk) begin
    if (!rst && ivalid) begin
      exp_fifo[wr_ptr % FIFO_DEPTH] <= golden_dot(vec0, vec1);
      wr_ptr       <= wr_ptr + 1;
      ivalid_count <= ivalid_count + 1;
    end
  end

  // Pop and compare for every valid output.
  always @(posedge clk) begin
    if (!rst && ovalid) begin
      exp_val      = exp_fifo[rd_ptr % FIFO_DEPTH];
      rd_ptr       <= rd_ptr + 1;
      ovalid_count <= ovalid_count + 1;

      if (wr_ptr == rd_ptr) begin
        // ovalid asserted with no matching input queued.
        error_count <= error_count + 1;
        $display("[%0t] ERROR: ovalid asserted but scoreboard is empty (unexpected output).", $time);
      end
      else if ((^result) === 1'bx) begin
        error_count <= error_count + 1;
        $display("[%0t] ERROR: result contains X/Z (result=%h), expected %0d.",
                 $time, result, exp_val);
      end
      else if (result !== exp_val[OWIDTH-1:0]) begin
        error_count <= error_count + 1;
        $display("[%0t] ERROR: result mismatch. got=%0d (0x%0h) expected=%0d.",
                 $time, $signed(result), result, exp_val);
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Stimulus helpers
  // ---------------------------------------------------------------------------
  // Drive one cycle of input (call is aligned to the negedge).
  task automatic drive(input logic [N*IWIDTH-1:0] a,
                       input logic [N*IWIDTH-1:0] b,
                       input logic                v);
    begin
      @(negedge clk);
      vec0   = a;
      vec1   = b;
      ivalid = v;
    end
  endtask

  // Drive an idle (bubble) cycle.
  task automatic idle();
    begin
      @(negedge clk);
      vec0   = '0;
      vec1   = '0;
      ivalid = 1'b0;
    end
  endtask

  // Random signed IWIDTH-bit value.
  function automatic logic signed [IWIDTH-1:0] rnd_elem();
    begin
      rnd_elem = $random;   // truncates to IWIDTH bits, interpreted as signed
    end
  endfunction

  function automatic logic [N*IWIDTH-1:0] rnd_vec();
    int i;
    logic [N*IWIDTH-1:0] v;
    begin
      v = '0;
      for (i = 0; i < N; i++)
        v[i*IWIDTH +: IWIDTH] = rnd_elem();
      rnd_vec = v;
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Test sequence
  // ---------------------------------------------------------------------------
  localparam logic signed [IWIDTH-1:0] IMAX = (1 <<< (IWIDTH-1)) - 1;  //  127
  localparam logic signed [IWIDTH-1:0] IMIN = -(1 <<< (IWIDTH-1));     // -128

  int i;

  initial begin
    // ---- init & reset ----
    rst    = 1'b1;
    ivalid = 1'b0;
    vec0   = '0;
    vec1   = '0;
    repeat (4) @(negedge clk);
    rst = 1'b0;

    // ---- directed tests (back-to-back to exercise full pipelining) ----
    // 1) all zeros -> 0
    drive(pack8(0,0,0,0,0,0,0,0), pack8(0,0,0,0,0,0,0,0), 1'b1);
    // 2) all ones  -> 8
    drive(pack8(1,1,1,1,1,1,1,1), pack8(1,1,1,1,1,1,1,1), 1'b1);
    // 3) 1..8 dot 1..8 -> sum of squares = 204
    drive(pack8(1,2,3,4,5,6,7,8), pack8(1,2,3,4,5,6,7,8), 1'b1);
    // 4) -1 dot +1 -> -8
    drive(pack8(-1,-1,-1,-1,-1,-1,-1,-1), pack8(1,1,1,1,1,1,1,1), 1'b1);
    // 5) all max * all max -> 8 * 127*127 = 129032
    drive(pack8(IMAX,IMAX,IMAX,IMAX,IMAX,IMAX,IMAX,IMAX),
          pack8(IMAX,IMAX,IMAX,IMAX,IMAX,IMAX,IMAX,IMAX), 1'b1);
    // 6) min * max -> 8 * (-128*127) = -130048  (most negative-ish)
    drive(pack8(IMIN,IMIN,IMIN,IMIN,IMIN,IMIN,IMIN,IMIN),
          pack8(IMAX,IMAX,IMAX,IMAX,IMAX,IMAX,IMAX,IMAX), 1'b1);
    // 7) min * min -> 8 * 16384 = 131072  (most positive)
    drive(pack8(IMIN,IMIN,IMIN,IMIN,IMIN,IMIN,IMIN,IMIN),
          pack8(IMIN,IMIN,IMIN,IMIN,IMIN,IMIN,IMIN,IMIN), 1'b1);
    // 8) mixed signs / distinct per-lane values
    drive(pack8(-8,7,-6,5,-4,3,-2,1), pack8(2,-3,4,-5,6,-7,8,-1), 1'b1);

    // ---- gaps in ivalid (make sure valid tracks correctly through pipeline) ----
    idle();
    drive(pack8(10,20,30,40,-10,-20,-30,-40),
          pack8(-1,2,-3,4,-5,6,-7,8), 1'b1);
    idle();
    idle();
    drive(pack8(3,3,3,3,3,3,3,3), pack8(3,3,3,3,3,3,3,3), 1'b1);

    // ---- randomized back-to-back stream ----
    for (i = 0; i < 500; i++)
      drive(rnd_vec(), rnd_vec(), 1'b1);

    // ---- randomized stream with random bubbles ----
    for (i = 0; i < 500; i++)
      drive(rnd_vec(), rnd_vec(), ($random % 3) != 0);

    // stop driving new inputs
    idle();

    // ---- drain the pipeline: wait until every input has produced an output ----
    fork : drain
      begin
        while (ovalid_count < ivalid_count) @(negedge clk);
      end
      begin
        // safety timeout in case the pipeline never drains
        repeat (200) @(negedge clk);
        $display("[%0t] ERROR: timeout draining pipeline (got %0d of %0d outputs).",
                 $time, ovalid_count, ivalid_count);
        error_count = error_count + 1;
      end
    join_any
    disable drain;

    // give one more cycle to catch any spurious extra ovalid
    repeat (2) @(negedge clk);

    // ---- final checks & report ----
    if (ivalid_count != ovalid_count) begin
      error_count = error_count + 1;
      $display("ERROR: input/output count mismatch: %0d inputs, %0d outputs.",
               ivalid_count, ovalid_count);
    end

    $display("----------------------------------------------------------------");
    $display("dot8 testbench summary: inputs=%0d outputs=%0d errors=%0d",
             ivalid_count, ovalid_count, error_count);
    if (error_count == 0)
      $display("RESULT: *** ALL TESTS PASSED ***");
    else
      $display("RESULT: *** %0d FAILURE(S) DETECTED ***", error_count);
    $display("----------------------------------------------------------------");

    $finish;
  end

  // Global watchdog so the sim can never hang forever.
  initial begin
    #500000;
    $display("ERROR: global timeout reached.");
    $finish;
  end

endmodule
