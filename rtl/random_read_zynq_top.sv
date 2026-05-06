// rtl/random_read_zynq_top.sv
`timescale 1ns/1ps
module random_read_zynq_top (
  input  logic SYSCLK_P,
  input  logic SYSCLK_N,
  input  logic RESETN,
  input  logic START_N,
  input  logic [1:0] MODE,
  output logic [7:0] LED
);
  import rrz_pkg::*;

  logic clk_ibuf;
  logic clk_fb;
  logic clk_fb_buf;
  logic clk_mmcm;
  logic clk;
  logic mmcm_locked;
  logic resetn_sync;
  logic locked_sync;
  logic rst_n;
  logic start_level;
  logic start_level_d;
  logic start_pulse;
  logic [1:0] mode_sync;
  logic [24:0] heartbeat;

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

  (* mark_debug = "true" *) logic dbg_busy;
  (* mark_debug = "true" *) logic dbg_done;
  (* mark_debug = "true" *) logic dbg_pass;
  (* mark_debug = "true" *) logic [1:0] dbg_mode;
  (* mark_debug = "true" *) logic [STATE_W-1:0] dbg_state;
  (* mark_debug = "true" *) logic [SCENARIO_W-1:0] dbg_scenario;
  (* mark_debug = "true" *) logic [31:0] dbg_mode_cycle_count;
  (* mark_debug = "true" *) logic [31:0] dbg_mode_input_request_count;
  (* mark_debug = "true" *) logic [31:0] dbg_mode_burst_count;
  (* mark_debug = "true" *) logic [31:0] dbg_mode_issued_beat_count;
  (* mark_debug = "true" *) logic [31:0] dbg_mode_useful_count;
  (* mark_debug = "true" *) logic [31:0] dbg_mode_discarded_count;
  (* mark_debug = "true" *) logic [31:0] dbg_mode_merged_count;
  (* mark_debug = "true" *) logic [31:0] dbg_mode_late_miss_count;
  (* mark_debug = "true" *) logic [31:0] dbg_mode_order_error_count;
  (* mark_debug = "true" *) logic [31:0] dbg_mode_reorder_stall_count;
  (* mark_debug = "true" *) logic [31:0] dbg_mode_s4_late_miss_count;

  IBUFDS #(
    .DIFF_TERM("TRUE"),
    .IBUF_LOW_PWR("FALSE"),
    .IOSTANDARD("LVDS_25")
  ) u_sysclk_ibufds (
    .I(SYSCLK_P),
    .IB(SYSCLK_N),
    .O(clk_ibuf)
  );

  BUFG u_sysclk_bufg (
    .I(clk_mmcm),
    .O(clk)
  );

  BUFG u_mmcm_fb_bufg (
    .I(clk_fb),
    .O(clk_fb_buf)
  );

  MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKIN1_PERIOD(5.000),
    .CLKFBOUT_MULT_F(5.000),
    .CLKFBOUT_PHASE(0.000),
    .DIVCLK_DIVIDE(1),
    .CLKOUT0_DIVIDE_F(10.000),
    .CLKOUT0_DUTY_CYCLE(0.500),
    .CLKOUT0_PHASE(0.000),
    .STARTUP_WAIT("FALSE")
  ) u_clk_mmcm (
    .CLKIN1(clk_ibuf),
    .CLKFBIN(clk_fb_buf),
    .CLKFBOUT(clk_fb),
    .CLKFBOUTB(),
    .CLKOUT0(clk_mmcm),
    .CLKOUT0B(),
    .CLKOUT1(),
    .CLKOUT1B(),
    .CLKOUT2(),
    .CLKOUT2B(),
    .CLKOUT3(),
    .CLKOUT3B(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKOUT6(),
    .LOCKED(mmcm_locked),
    .PWRDWN(1'b0),
    .RST(~RESETN)
  );

  xpm_cdc_single #(
    .DEST_SYNC_FF(4),
    .INIT_SYNC_FF(0),
    .SIM_ASSERT_CHK(0),
    .SRC_INPUT_REG(0)
  ) u_resetn_cdc (
    .src_clk(1'b0),
    .src_in(RESETN),
    .dest_clk(clk),
    .dest_out(resetn_sync)
  );

  xpm_cdc_single #(
    .DEST_SYNC_FF(4),
    .INIT_SYNC_FF(0),
    .SIM_ASSERT_CHK(0),
    .SRC_INPUT_REG(0)
  ) u_locked_cdc (
    .src_clk(1'b0),
    .src_in(mmcm_locked),
    .dest_clk(clk),
    .dest_out(locked_sync)
  );

  assign rst_n = resetn_sync && locked_sync;

  xpm_cdc_single #(
    .DEST_SYNC_FF(3),
    .INIT_SYNC_FF(0),
    .SIM_ASSERT_CHK(0),
    .SRC_INPUT_REG(0)
  ) u_start_cdc (
    .src_clk(1'b0),
    .src_in(~START_N),
    .dest_clk(clk),
    .dest_out(start_level)
  );

  genvar mode_g;
  generate
    for (mode_g = 0; mode_g < 2; mode_g++) begin : g_mode_cdc
      xpm_cdc_single #(
        .DEST_SYNC_FF(3),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(0)
      ) u_mode_cdc (
        .src_clk(1'b0),
        .src_in(MODE[mode_g]),
        .dest_clk(clk),
        .dest_out(mode_sync[mode_g])
      );
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      start_level_d <= 1'b0;
      heartbeat <= '0;
    end else begin
      start_level_d <= start_level;
      heartbeat <= heartbeat + 25'd1;
    end
  end

  assign start_pulse = start_level && !start_level_d;

  random_read_core u_random_read_core (
    .clk(clk),
    .rst_n(rst_n),
    .start(start_pulse),
    .mode_sel(mode_sync),
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

  assign LED[0] = busy;
  assign LED[1] = done;
  assign LED[2] = pass;
  assign LED[3] = active_mode_dbg[0];
  assign LED[4] = active_mode_dbg[1];
  assign LED[5] = done && (mode_merged_count != 32'd0);
  assign LED[6] = done && (mode_late_miss_count != 32'd0);
  assign LED[7] = heartbeat[24];

  assign dbg_busy = busy;
  assign dbg_done = done;
  assign dbg_pass = pass;
  assign dbg_mode = active_mode_dbg;
  assign dbg_state = state_dbg;
  assign dbg_scenario = scenario_dbg;
  assign dbg_mode_cycle_count = mode_cycle_count;
  assign dbg_mode_input_request_count = mode_input_request_count;
  assign dbg_mode_burst_count = mode_burst_count;
  assign dbg_mode_issued_beat_count = mode_issued_beat_count;
  assign dbg_mode_useful_count = mode_useful_count;
  assign dbg_mode_discarded_count = mode_discarded_count;
  assign dbg_mode_merged_count = mode_merged_count;
  assign dbg_mode_late_miss_count = mode_late_miss_count;
  assign dbg_mode_order_error_count = mode_order_error_count;
  assign dbg_mode_reorder_stall_count = mode_reorder_stall_count;
  assign dbg_mode_s4_late_miss_count = mode_s4_late_miss_count;

  logic unused_top;
  assign unused_top = ^{
    mode_output_count[0],
    mode_s0_burst_count[0],
    mode_s1_merge_count[0],
    mode_s2_merge_count[0],
    mode_s3_merge_count[0],
    mode_s5_merge_count[0],
    mode_s6_merge_count[0],
    mode_s7_merge_count[0]
  };
endmodule
