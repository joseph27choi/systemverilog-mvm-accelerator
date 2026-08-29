// =============================================================================
// ctrl_tb.sv  -  Self-checking unit testbench for the ctrl module (ECE 327 Lab 4)
//
// The controller is a 2-state FSM (IDLE / COMPUTE). On `start` it walks the
// vector/matrix read addresses and accumulator control bits for the whole
// operation. From the handout, with vec_start_addr=8, vec_num_words=4,
// mat_start_addr=0, mat_num_rows_per_olane=2 the emitted sequence is:
//
//   vec_raddr= 8 mat_raddr=0 first=1 last=0 busy=1 ovalid=1
//   vec_raddr= 9 mat_raddr=1 first=0 last=0 busy=1 ovalid=1
//   vec_raddr=10 mat_raddr=2 first=0 last=0 busy=1 ovalid=1
//   vec_raddr=11 mat_raddr=3 first=0 last=1 busy=1 ovalid=1
//   vec_raddr= 8 mat_raddr=4 first=1 last=0 busy=1 ovalid=1
//   vec_raddr= 9 mat_raddr=5 first=0 last=0 busy=1 ovalid=1
//   vec_raddr=10 mat_raddr=6 first=0 last=0 busy=1 ovalid=1
//   vec_raddr=11 mat_raddr=7 first=0 last=1 busy=1 ovalid=1
//
// Reference model (for r in 0..rows-1, w in 0..num_words-1):
//   vec_raddr   = vec_start_addr + w                     (restarts each row)
//   mat_raddr   = mat_start_addr + (r*num_words + w)     (continuous counter)
//   accum_first = (w == 0)
//   accum_last  = (w == num_words-1)
//   ovalid/busy = 1                                      (during generation)
// =============================================================================
`timescale 1ns / 1ps

module ctrl_tb;

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------
  localparam int VEC_ADDRW  = 8;
  localparam int MAT_ADDRW  = 12;
  localparam int VEC_SIZEW  = VEC_ADDRW + 1;  // Match ctrl.sv default (9 bits, holds up to 511)
  localparam int MAT_SIZEW  = MAT_ADDRW + 1;  // Match ctrl.sv default (13 bits)
  localparam int CLK_PERIOD = 10;

  // ---------------------------------------------------------------------------
  // DUT signals
  // ---------------------------------------------------------------------------
  logic                  clk;
  logic                  rst;
  logic                  start;
  logic [VEC_ADDRW-1:0]  vec_start_addr;
  logic [VEC_SIZEW-1:0]  vec_num_words;
  logic [MAT_ADDRW-1:0]  mat_start_addr;
  logic [MAT_SIZEW-1:0]  mat_num_rows_per_olane;
  logic [VEC_ADDRW-1:0]  vec_raddr;
  logic [MAT_ADDRW-1:0]  mat_raddr;
  logic                  accum_first;
  logic                  accum_last;
  logic                  ovalid;
  logic                  busy;

  // ---------------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------------
  ctrl #(
    .VEC_ADDRW (VEC_ADDRW),
    .MAT_ADDRW (MAT_ADDRW),
    .VEC_SIZEW (VEC_SIZEW),
    .MAT_SIZEW (MAT_SIZEW)
  ) dut (
    .clk                    (clk),
    .rst                    (rst),
    .start                  (start),
    .vec_start_addr         (vec_start_addr),
    .vec_num_words          (vec_num_words),
    .mat_start_addr         (mat_start_addr),
    .mat_num_rows_per_olane (mat_num_rows_per_olane),
    .vec_raddr              (vec_raddr),
    .mat_raddr              (mat_raddr),
    .accum_first            (accum_first),
    .accum_last             (accum_last),
    .ovalid                 (ovalid),
    .busy                   (busy)
  );

  // ---------------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------------
  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ---------------------------------------------------------------------------
  // Bookkeeping
  // ---------------------------------------------------------------------------
  int num_runs   = 0;
  int num_errors = 0;

  // Collection queues
  int cv [$];
  int cm [$];
  int cf [$];
  int cl [$];

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------
  task automatic do_reset();
    rst                    = 1'b1;
    start                  = 1'b0;
    vec_start_addr         = '0;
    vec_num_words          = '0;
    mat_start_addr         = '0;
    mat_num_rows_per_olane = '0;
    repeat (3) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);
    check_idle("after-reset");
  endtask

  // ---------------------------------------------------------------------------
  // Verify IDLE-state outputs are all deasserted
  // ---------------------------------------------------------------------------
  task automatic check_idle(input string ctx);
    if (busy !== 1'b0 || ovalid !== 1'b0 ||
        accum_first !== 1'b0 || accum_last !== 1'b0) begin
      $error("[%0t] IDLE check FAILED (%s): busy=%0b ovalid=%0b first=%0b last=%0b (expected all 0)",
             $time, ctx, busy, ovalid, accum_first, accum_last);
      num_errors++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Run one MVM control sequence and self-check it.
  // ---------------------------------------------------------------------------
  task automatic run_mvm(input int    vsa,
                         input int    vnw,
                         input int    msa,
                         input int    rows,
                         input string name);
    int wd;
    int exp_len;
    int idx;
    int run_errs;
    int r, w;
    int gv, gm, gf, gl;

    num_runs++;
    run_errs = num_errors;

    cv.delete(); cm.delete(); cf.delete(); cl.delete();

    // Present operand parameters while in IDLE and let them register
    @(negedge clk);
    vec_start_addr         = vsa;
    vec_num_words          = vnw;
    mat_start_addr         = msa;
    mat_num_rows_per_olane = rows;
    @(negedge clk);

    // One-cycle start pulse
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    // Wait for the controller to begin emitting valid control (ovalid)
    wd = 0;
    while (!ovalid && wd < 200) begin
      @(negedge clk);
      wd++;
    end
    if (!ovalid) begin
      $error("[%0t] %s: ovalid never asserted after start", $time, name);
      num_errors++;
      return;
    end

    // Capture the full sequence while ovalid is asserted
    while (ovalid) begin
      cv.push_back(int'(vec_raddr));
      cm.push_back(int'(mat_raddr));
      cf.push_back(int'(accum_first));
      cl.push_back(int'(accum_last));
      if (busy !== 1'b1) begin
        $error("[%0t] %s: busy must be high while ovalid is asserted (sample %0d)",
               $time, name, cv.size()-1);
        num_errors++;
      end
      @(negedge clk);
    end

    // --- Compare against the golden reference model --------------------------
    exp_len = vnw * rows;
    if (cv.size() != exp_len) begin
      $error("[%0t] %s: emitted %0d control cycles, expected %0d",
             $time, name, cv.size(), exp_len);
      num_errors++;
    end

    idx = 0;
    for (r = 0; r < rows; r++) begin
      for (w = 0; w < vnw; w++) begin
        gv = vsa + w;
        gm = msa + (r * vnw + w);
        gf = (w == 0)     ? 1 : 0;
        gl = (w == vnw-1) ? 1 : 0;

        if (idx < cv.size()) begin
          if (cv[idx] != gv || cm[idx] != gm ||
              cf[idx] != gf || cl[idx] != gl) begin
            $error("[%0t] %s: mismatch @cycle %0d  got: vec=%0d mat=%0d first=%0b last=%0b  exp: vec=%0d mat=%0d first=%0b last=%0b",
                   $time, name, idx,
                   cv[idx], cm[idx], cf[idx], cl[idx],
                   gv, gm, gf, gl);
            num_errors++;
          end
        end
        idx++;
      end
    end

    // busy must eventually return low, and FSM back to IDLE
    wd = 0;
    while (busy && wd < 200) begin @(negedge clk); wd++; end
    if (busy) begin
      $error("[%0t] %s: busy never returned to 0 after the sequence", $time, name);
      num_errors++;
    end
    check_idle({name, "-post"});

    if (num_errors == run_errs)
      $display("[%0t] PASS  %-20s (%0d cycles: vnw=%0d rows=%0d vsa=%0d msa=%0d)",
               $time, name, exp_len, vnw, rows, vsa, msa);
    else
      $display("[%0t] FAIL  %-20s (see errors above)", $time, name);

    // settle back to IDLE before next run
    repeat (3) @(negedge clk);
  endtask

  // ---------------------------------------------------------------------------
  // Main stimulus
  // ---------------------------------------------------------------------------
  initial begin
    int t;
    int vnw_r, rows_r, vsa_r, msa_r;

    $dumpfile("ctrl_tb.vcd");
    $dumpvars(0, ctrl_tb);

    do_reset();

    // --- Test 1: the exact example from the handout --------------------------
    $display("\n--- Test 1: handout example (vsa=8, vnw=4, msa=0, rows=2) ---");
    run_mvm(8, 4, 0, 2, "handout_example");

    // --- Test 2: single row --------------------------------------------------
    $display("\n--- Test 2: single row ---");
    run_mvm(0, 4, 0, 1, "single_row");

    // --- Test 3: single word per row (first & last both set) -----------------
    $display("\n--- Test 3: single word per row ---");
    run_mvm(3, 1, 10, 3, "single_word");

    // --- Test 4: non-zero start addresses ------------------------------------
    $display("\n--- Test 4: non-zero start addresses ---");
    run_mvm(5, 8, 100, 4, "nonzero_starts");

    // --- Test 5: larger sequence (N=512 => 64 words) -------------------------
    $display("\n--- Test 5: 64 words x 3 rows ---");
    run_mvm(0, 64, 0, 3, "big_64x3");

    // --- Test 6: back-to-back operations (FSM must re-arm) -------------------
    $display("\n--- Test 6: back-to-back runs ---");
    run_mvm(2, 2, 20, 2, "b2b_A");
    run_mvm(9, 3, 40, 2, "b2b_B");

    // --- Test 7: randomized runs ---------------------------------------------
    $display("\n--- Test 7: randomized runs ---");
    for (t = 0; t < 30; t++) begin
      vnw_r  = $urandom_range(1, 20);
      rows_r = $urandom_range(1, 8);
      vsa_r  = $urandom_range(0, 40);
      msa_r  = $urandom_range(0, 200);
      run_mvm(vsa_r, vnw_r, msa_r, rows_r, $sformatf("rand%0d", t));
    end

    // ---------------------------------------------------------------------------
    // Report
    // ---------------------------------------------------------------------------
    $display("\n=====================================================");
    $display(" ctrl_tb finished: %0d run(s), %0d error(s)", num_runs, num_errors);
    if (num_errors == 0) $display(" RESULT: ALL TESTS PASSED");
    else                 $display(" RESULT: %0d FAILURE(S)", num_errors);
    $display("=====================================================\n");

    $finish;
  end

  // ---------------------------------------------------------------------------
  // Watchdog
  // ---------------------------------------------------------------------------
  initial begin
    #(CLK_PERIOD * 200000);
    $error("TIMEOUT: simulation did not finish.");
    $finish;
  end

endmodule
