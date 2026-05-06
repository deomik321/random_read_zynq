// tb/tb_random_read_zynq.sv
`timescale 1ns/1ps
module tb_random_read_zynq;
  import rrz_pkg::*;

  logic clk;
  logic rst_n;
  logic start;
  logic [1:0] mode_sel;

  logic busy;
  logic done;
  logic pass;
  logic [STATE_W-1:0] state_dbg;
  logic [SCENARIO_W-1:0] scenario_dbg;
  logic [1:0] active_mode_dbg;
  logic [31:0] mode_cycle_count;
  logic [31:0] mode_input_request_count;
  logic [31:0] mode_burst_count;
  logic [31:0] mode_issued_beat_count;
  logic [31:0] mode_useful_count;
  logic [31:0] mode_discarded_count;
  logic [31:0] mode_merged_count;
  logic [31:0] mode_late_miss_count;
  logic [31:0] mode_output_count;
  logic [31:0] mode_order_error_count;
  logic [31:0] mode_reorder_stall_count;
  logic [31:0] mode_s0_burst_count;
  logic [31:0] mode_s1_merge_count;
  logic [31:0] mode_s2_merge_count;
  logic [31:0] mode_s3_merge_count;
  logic [31:0] mode_s4_late_miss_count;
  logic [31:0] mode_s5_merge_count;
  logic [31:0] mode_s6_merge_count;
  logic [31:0] mode_s7_merge_count;

  random_read_core dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .mode_sel(mode_sel),
    .busy(busy),
    .done(done),
    .pass(pass),
    .state_dbg(state_dbg),
    .scenario_dbg(scenario_dbg),
    .active_mode_dbg(active_mode_dbg),
    .mode_cycle_count(mode_cycle_count),
    .mode_input_request_count(mode_input_request_count),
    .mode_burst_count(mode_burst_count),
    .mode_issued_beat_count(mode_issued_beat_count),
    .mode_useful_count(mode_useful_count),
    .mode_discarded_count(mode_discarded_count),
    .mode_merged_count(mode_merged_count),
    .mode_late_miss_count(mode_late_miss_count),
    .mode_output_count(mode_output_count),
    .mode_order_error_count(mode_order_error_count),
    .mode_reorder_stall_count(mode_reorder_stall_count),
    .mode_s0_burst_count(mode_s0_burst_count),
    .mode_s1_merge_count(mode_s1_merge_count),
    .mode_s2_merge_count(mode_s2_merge_count),
    .mode_s3_merge_count(mode_s3_merge_count),
    .mode_s4_late_miss_count(mode_s4_late_miss_count),
    .mode_s5_merge_count(mode_s5_merge_count),
    .mode_s6_merge_count(mode_s6_merge_count),
    .mode_s7_merge_count(mode_s7_merge_count)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic pulse_start;
    begin
      repeat (8) @(posedge clk);
      start = 1'b1;
      @(posedge clk);
      start = 1'b0;
    end
  endtask

  task automatic print_summary(input logic [1:0] mode);
    longint unsigned waste_permille;
    longint unsigned useful_permille;
    longint unsigned req_per_burst_x100;
    begin
      waste_permille = (mode_issued_beat_count == 0) ? 0 :
                       (longint'(mode_discarded_count) * 1000) / mode_issued_beat_count;
      useful_permille = (mode_issued_beat_count == 0) ? 0 :
                        (longint'(mode_useful_count) * 1000) / mode_issued_beat_count;
      req_per_burst_x100 = (mode_burst_count == 0) ? 0 :
                           (longint'(mode_input_request_count) * 100) / mode_burst_count;

      $display("");
      case (mode)
        2'd0: $display("==== mode 0: one request -> fixed 16-beat read package ====");
        2'd1: $display("==== mode 1: range merge, no reorder buffer ====");
        default: $display("==== mode 2: range merge, reorder buffer enabled ====");
      endcase
      $display("cycle_count             = %0d", mode_cycle_count);
      $display("input_request_count     = %0d", mode_input_request_count);
      $display("issued_burst_count      = %0d", mode_burst_count);
      $display("issued_beat_count       = %0d", mode_issued_beat_count);
      $display("useful_output_count     = %0d", mode_useful_count);
      $display("discarded_overfetch     = %0d", mode_discarded_count);
      $display("merged_request_count    = %0d", mode_merged_count);
      $display("late_miss_count         = %0d", mode_late_miss_count);
      $display("final_output_count      = %0d", mode_output_count);
      $display("order_error_count       = %0d", mode_order_error_count);
      $display("reorder_stall_count     = %0d", mode_reorder_stall_count);
      $display("requests_per_burst_x100 = %0d", req_per_burst_x100);
      $display("useful_data_permille    = %0d", useful_permille);
      $display("discarded_permille      = %0d", waste_permille);
      $display("discarded_per_request   = %0d", mode_discarded_count / TRACE_LEN);
      $display("scenario0 no-merge bursts = %0d", mode_s0_burst_count);
      $display("scenario1 late-hit merges = %0d", mode_s1_merge_count);
      $display("scenario2 multi-hit merge = %0d", mode_s2_merge_count);
      $display("scenario3 boundary merge  = %0d", mode_s3_merge_count);
      $display("scenario4 expired misses  = %0d", mode_s4_late_miss_count);
      $display("scenario5 overlap merges  = %0d", mode_s5_merge_count);
      $display("scenario6 dense merges    = %0d", mode_s6_merge_count);
      $display("scenario7 mixed merges    = %0d", mode_s7_merge_count);
      $display("pass                    = %0d", pass);
    end
  endtask

  task automatic check_mode(input logic [1:0] mode);
    begin
      assert (pass)
        else $fatal(1, "mode %0d pass flag is low", mode);
      assert (mode_input_request_count == TRACE_LEN)
        else $fatal(1, "mode %0d input request count mismatch", mode);
      assert (mode_useful_count == TRACE_LEN)
        else $fatal(1, "mode %0d useful count mismatch", mode);
      assert (mode_output_count == TRACE_LEN)
        else $fatal(1, "mode %0d output count mismatch", mode);

      case (mode)
        2'd0: begin
          assert (mode_burst_count == TRACE_LEN)
            else $fatal(1, "mode 0 must issue one burst per request");
          assert (mode_issued_beat_count == TRACE_LEN * MAX_BURST_LEN)
            else $fatal(1, "mode 0 must issue fixed 16-beat bursts");
          assert (mode_discarded_count == TRACE_LEN * (MAX_BURST_LEN - 1))
            else $fatal(1, "mode 0 must expose fixed-burst overfetch waste");
          assert (mode_merged_count == 32'd0)
            else $fatal(1, "mode 0 must not merge");
          assert (mode_order_error_count == 32'd0)
            else $fatal(1, "mode 0 must preserve request order");
        end
        2'd1: begin
          assert (mode_burst_count < TRACE_LEN)
            else $fatal(1, "mode 1 burst count did not decrease");
          assert (mode_merged_count > 0)
            else $fatal(1, "mode 1 did not merge any request");
          assert (mode_late_miss_count > 0)
            else $fatal(1, "mode 1 did not report window-expired late miss");
          assert (mode_discarded_count > 0)
            else $fatal(1, "mode 1 should show overfetch cost");
          assert (mode_order_error_count > 0)
            else $fatal(1, "mode 1 should expose out-of-order useful responses");
        end
        default: begin
          assert (mode_burst_count < TRACE_LEN)
            else $fatal(1, "mode 2 burst count did not decrease");
          assert (mode_merged_count > 0)
            else $fatal(1, "mode 2 did not merge any request");
          assert (mode_late_miss_count > 0)
            else $fatal(1, "mode 2 did not report window-expired late miss");
          assert (mode_discarded_count > 0)
            else $fatal(1, "mode 2 should show overfetch cost");
          assert (mode_order_error_count == 32'd0)
            else $fatal(1, "mode 2 reorder buffer should remove order errors");
          assert (mode_reorder_stall_count > 0)
            else $fatal(1, "mode 2 should show reorder stall cost");
        end
      endcase
    end
  endtask

  task automatic run_case(input logic [1:0] mode);
    int timeout;
    begin
      mode_sel = mode;
      pulse_start();

      timeout = 0;
      while (!done) begin
        @(posedge clk);
        timeout++;
        if (timeout > 50000) begin
          $fatal(1, "mode %0d done timeout", mode);
        end
      end

      print_summary(mode);
      check_mode(mode);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    start = 1'b0;
    mode_sel = 2'd0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (10) @(posedge clk);

    run_case(2'd0);
    run_case(2'd1);
    run_case(2'd2);

    $display("");
    $display("All random_read_zynq mode tests passed.");
    #100;
    $finish;
  end

  logic unused_tb;
  assign unused_tb = ^{busy, state_dbg, scenario_dbg, active_mode_dbg};
endmodule
