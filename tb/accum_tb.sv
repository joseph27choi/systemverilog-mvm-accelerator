// =============================================================================
// accum_tb.sv  -  Self-checking unit testbench for the accum module (ECE 327 Lab 4)
//
// Verifies the accumulator described in the lab handout:
//   - ivalid : input `data` is valid and should be accumulated
//   - first  : start of a new accumulation (reset accum register to `data`)
//   - last   : last input in the current accumulation (assert ovalid afterwards)
//   - result : ACCUMW-wide accumulated sum
//   - ovalid : asserted when `result` holds the final sum of an accumulation
//
// Methodology:
//   * Inputs are driven on the negative clock edge so they are stable before
//     the posedge at which the DUT samples them.
//   * A reference model computes the expected sum of each accumulation group
//     and pushes it into a scoreboard queue.
//   * The checker watches for `ovalid` (sampled on negedge, after registered
//     outputs have settled) and compares `result` against the queued expected
//     value. Driving the check off `ovalid` makes it robust to whether the
//     design asserts ovalid in the same cycle or one cycle after `last`.
//
// NOTE: This assumes the standard *registered* accumulator (recommended for
//       meeting timing). If your accum uses a different output latency, the
//       ovalid-driven checker still works as long as `result` is valid while
//       `ovalid` is high.
// =============================================================================
`timescale 1ns / 1ps

module accum_tb;

  // ---------------------------------------------------------------------------
  // Parameters  (adjust to match your instantiation if needed)
  //   DATAW  = width of the input data (dot-product result width in the MVM)
  //   ACCUMW = width of the internal accumulator / result
  // Defaults chosen so that signed sign-extension (DATAW < ACCUMW) is exercised.
  // ---------------------------------------------------------------------------
  localparam int DATAW      = 16;
  localparam int ACCUMW     = 32;
  localparam int CLK_PERIOD = 10;   // ns

  // ---------------------------------------------------------------------------
  // DUT signals
  // ---------------------------------------------------------------------------
  logic                     clk;
  logic                     rst;
  logic signed [DATAW-1:0]  data;
  logic                     ivalid;
  logic                     first;
  logic                     last;
  logic signed [ACCUMW-1:0] result;
  logic                     ovalid;

  // ---------------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------------
  accum #(
    .DATAW  (DATAW),
    .ACCUMW (ACCUMW)
  ) dut (
    .clk    (clk),
    .rst    (rst),
    .data   (data),
    .ivalid (ivalid),
    .first  (first),
    .last   (last),
    .result (result),
    .ovalid (ovalid)
  );

  // ---------------------------------------------------------------------------
  // Clock generation
  // ---------------------------------------------------------------------------
  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ---------------------------------------------------------------------------
  // Scoreboard
  // ---------------------------------------------------------------------------
  logic signed [ACCUMW-1:0] expected_q [$];   // expected final sums, in order
  string                    label_q    [$];   // human-readable label per group
  int                       num_checks = 0;
  int                       num_errors = 0;

  // ---------------------------------------------------------------------------
  // Checker: sample on negedge so registered outputs from the preceding
  // posedge are stable. Compare whenever ovalid is asserted.
  // ---------------------------------------------------------------------------
  always @(negedge clk) begin
    if (!rst && ovalid) begin
      if (expected_q.size() == 0) begin
        $error("[%0t] Unexpected ovalid! result=%0d but no result was queued.",
               $time, result);
        num_errors++;
      end
      else begin
        automatic logic signed [ACCUMW-1:0] exp = expected_q.pop_front();
        automatic string                    lbl = label_q.pop_front();
        num_checks++;
        if (result === exp) begin
          $display("[%0t] PASS  %-24s result=%0d", $time, lbl, result);
        end
        else begin
          $error("[%0t] FAIL  %-24s result=%0d  expected=%0d",
                 $time, lbl, result, exp);
          num_errors++;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Low-level driver: apply one input on the negedge so it is stable at posedge
  // ---------------------------------------------------------------------------
  task automatic drive(input logic signed [DATAW-1:0] d,
                       input logic                    v,
                       input logic                    f,
                       input logic                    l);
    @(negedge clk);
    data   = d;
    ivalid = v;
    first  = f;
    last   = l;
  endtask

  // Drive one idle (bubble) cycle: accumulator must hold its state
  task automatic idle(input int n = 1);
    repeat (n) drive('0, 1'b0, 1'b0, 1'b0);
  endtask

  // ---------------------------------------------------------------------------
  // Run one accumulation group.
  //   vals       : the sequence of values to accumulate
  //   max_bubble : if > 0, insert 0..max_bubble idle cycles before each element
  //   name       : label for reporting
  // Pushes the expected final sum onto the scoreboard.
  // ---------------------------------------------------------------------------
  task automatic run_group(input logic signed [DATAW-1:0] vals[],
                           input int                       max_bubble = 0,
                           input string                    name = "group");
    logic signed [ACCUMW-1:0] sum;
    int                       nb;
    sum = '0;
    foreach (vals[i]) begin
      if (max_bubble > 0) begin
        nb = $urandom_range(0, max_bubble);
        idle(nb);
      end
      if (i == 0) sum = vals[i];            // `first` -> load
      else        sum = sum + vals[i];      // otherwise accumulate
      drive(vals[i], 1'b1, (i == 0), (i == vals.size()-1));
    end
    expected_q.push_back(sum);
    label_q.push_back($sformatf("%s(n=%0d)", name, vals.size()));
  endtask

  // ---------------------------------------------------------------------------
  // Reset task
  // ---------------------------------------------------------------------------
  task automatic do_reset();
    rst    = 1'b1;
    data   = '0;
    ivalid = 1'b0;
    first  = 1'b0;
    last   = 1'b0;
    repeat (3) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);
  endtask

  // ---------------------------------------------------------------------------
  // Main stimulus
  // ---------------------------------------------------------------------------
  logic signed [DATAW-1:0] v[];

  initial begin
    // Optional VCD dump for waveform viewing
    $dumpfile("accum_tb.vcd");
    $dumpvars(0, accum_tb);

    do_reset();

    // --- Test 1: single-element accumulations (first==last in one cycle) -----
    $display("\n--- Test 1: single-element accumulations ---");
    v = '{ 16'sd5 };            run_group(v, 0, "single_5");
    v = '{ -16'sd3 };           run_group(v, 0, "single_-3");
    v = '{ 16'sd100 };          run_group(v, 0, "single_100");
    v = '{ 16'sh7FFF };         run_group(v, 0, "single_maxpos");
    v = '{ -16'sh8000 };        run_group(v, 0, "single_maxneg");
    idle(4);

    // --- Test 2: multi-element accumulation ----------------------------------
    $display("\n--- Test 2: multi-element accumulation ---");
    v = '{ 16'sd1, 16'sd2, 16'sd3, 16'sd4 };               // sum = 10
    run_group(v, 0, "1..4");
    idle(4);

    // --- Test 3: 8-element accumulation with negatives (signed check) --------
    $display("\n--- Test 3: 8-element with negatives ---");
    v = '{ 16'sd10, -16'sd20, 16'sd30, -16'sd40,
           16'sd50, -16'sd60, 16'sd70, -16'sd80 };          // sum = -40
    run_group(v, 0, "mixed8");
    idle(4);

    // --- Test 4: back-to-back accumulations (no idle between groups) ---------
    $display("\n--- Test 4: back-to-back accumulations ---");
    v = '{ 16'sd7, 16'sd7, 16'sd7 };   run_group(v, 0, "b2b_A");   // 21
    v = '{ -16'sd5, 16'sd5 };          run_group(v, 0, "b2b_B");   // 0
    v = '{ 16'sd1000 };                run_group(v, 0, "b2b_C");   // 1000
    idle(4);

    // --- Test 5: accumulation with random bubbles (accum must hold) ----------
    $display("\n--- Test 5: accumulation with idle bubbles ---");
    v = '{ 16'sd11, 16'sd22, 16'sd33, 16'sd44, 16'sd55 };  // 165
    run_group(v, 3, "bubbles");
    idle(4);

    // --- Test 6: `first` correctly reloads (ignores stale accumulator) -------
    // Run a group, then a new group whose `first` must discard the old sum.
    $display("\n--- Test 6: first reloads / discards stale state ---");
    v = '{ 16'sd500, 16'sd500 };       run_group(v, 0, "stale_A"); // 1000
    v = '{ 16'sd1, 16'sd2 };           run_group(v, 0, "reload_B"); // 3 (not 1003)
    idle(4);

    // --- Test 7: reset mid-stream, then a fresh accumulation -----------------
    $display("\n--- Test 7: reset then fresh accumulation ---");
    do_reset();
    v = '{ 16'sd9, 16'sd9, 16'sd9, 16'sd9 };   run_group(v, 0, "post_reset"); // 36
    idle(4);

    // --- Test 8: randomized accumulations ------------------------------------
    $display("\n--- Test 8: randomized accumulations ---");
    for (int g = 0; g < 50; g++) begin
      int len = $urandom_range(1, 12);
      v = new[len];
      foreach (v[i]) v[i] = $urandom;          // full-range random signed value
      run_group(v, $urandom_range(0, 2), $sformatf("rand%0d", g));
    end
    idle(8);

    // ---------------------------------------------------------------------------
    // Final report
    // ---------------------------------------------------------------------------
    if (expected_q.size() != 0) begin
      $error("%0d expected result(s) were never produced (missing ovalid).",
             expected_q.size());
      num_errors += expected_q.size();
    end

    $display("\n=====================================================");
    $display(" accum_tb finished: %0d checks, %0d error(s)", num_checks, num_errors);
    if (num_errors == 0) $display(" RESULT: ALL TESTS PASSED");
    else                 $display(" RESULT: %0d FAILURE(S)", num_errors);
    $display("=====================================================\n");

    $finish;
  end

  // ---------------------------------------------------------------------------
  // Watchdog: prevent a hung simulation if ovalid never fires
  // ---------------------------------------------------------------------------
  initial begin
    #(CLK_PERIOD * 5000);
    $error("TIMEOUT: simulation did not finish. Check ovalid generation.");
    $finish;
  end

endmodule