// rtl/random_read_core.sv
`timescale 1ns/1ps
module random_read_core #(
  parameter int BRAM_ADDR_W = 12,
  parameter int BRAM_DEPTH  = 4096
) (
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic [1:0] mode_sel,

  output logic busy,
  output logic done,
  output logic pass,
  output logic [rrz_pkg::STATE_W-1:0] state_dbg,
  output logic [rrz_pkg::SCENARIO_W-1:0] scenario_dbg,
  output logic [1:0] active_mode_dbg,

  output logic [31:0] mode_cycle_count,
  output logic [31:0] mode_input_request_count,
  output logic [31:0] mode_burst_count,
  output logic [31:0] mode_issued_beat_count,
  output logic [31:0] mode_useful_count,
  output logic [31:0] mode_discarded_count,
  output logic [31:0] mode_merged_count,
  output logic [31:0] mode_late_miss_count,
  output logic [31:0] mode_output_count,
  output logic [31:0] mode_order_error_count,
  output logic [31:0] mode_reorder_stall_count,
  output logic [31:0] mode_s0_burst_count,
  output logic [31:0] mode_s1_merge_count,
  output logic [31:0] mode_s2_merge_count,
  output logic [31:0] mode_s3_merge_count,
  output logic [31:0] mode_s4_late_miss_count,
  output logic [31:0] mode_s5_merge_count,
  output logic [31:0] mode_s6_merge_count,
  output logic [31:0] mode_s7_merge_count
);
  import rrz_pkg::*;

  typedef enum logic [STATE_W-1:0] {
    ST_IDLE  = 4'd0,
    ST_START = 4'd1,
    ST_WAIT  = 4'd2,
    ST_DONE  = 4'd3
  } state_t;

  state_t state;
  logic [1:0] mode_r;
  logic [1:0] normalized_mode;
  logic run_start;
  logic run_clear;
  logic run_full_burst_enable;
  logic run_merge_enable;
  logic run_reorder_enable;
  logic pass_condition;

  logic trace_start;
  logic trace_done;
  logic trace_req_valid;
  logic trace_req_ready;
  read_req_t trace_req;
  logic [31:0] trace_accepted_count;
  logic [SCENARIO_W-1:0] current_scenario;

  logic burst_valid;
  logic burst_ready;
  burst_desc_t burst_desc;
  logic merge_idle;
  logic merged_request_pulse;
  logic allocated_request_pulse;
  logic late_miss_pulse;
  logic [SCENARIO_W-1:0] merged_scenario;
  logic [SCENARIO_W-1:0] late_miss_scenario;
  logic [SCENARIO_W-1:0] issued_scenario;

  logic bram_en;
  logic [BRAM_ADDR_W-1:0] bram_addr;
  logic [DATA_W-1:0] bram_rdata;
  logic engine_rvalid;
  logic engine_rready;
  logic [DATA_W-1:0] engine_rdata;
  logic engine_ruseful;
  logic [TAG_W-1:0] engine_rtag;
  logic engine_rlast;
  logic engine_idle;
  logic discarded_beat_pulse;

  logic response_out_pulse;
  logic [DATA_W-1:0] response_out_data;
  logic [TAG_W-1:0] response_out_tag;
  logic response_idle;
  logic reorder_stall_pulse;

  logic [31:0] cycle_count;
  logic [31:0] input_request_count;
  logic [31:0] issued_burst_count;
  logic [31:0] issued_beat_count;
  logic [31:0] useful_count;
  logic [31:0] discarded_count;
  logic [31:0] merged_count;
  logic [31:0] late_miss_count;
  logic [31:0] output_count;
  logic [31:0] order_error_count;
  logic [31:0] reorder_stall_count;
  logic [TAG_W-1:0] expected_out_tag;
  logic run_complete;
  logic issued_burst_pulse;

  logic [31:0] scenario_input_count [NUM_SCENARIOS];
  logic [31:0] scenario_burst_count [NUM_SCENARIOS];
  logic [31:0] scenario_merge_count [NUM_SCENARIOS];
  logic [31:0] scenario_late_miss_count [NUM_SCENARIOS];

  (* mark_debug = "true" *) logic [1:0] dbg_mode;
  (* mark_debug = "true" *) logic [31:0] dbg_cycle_count;
  (* mark_debug = "true" *) logic [31:0] dbg_input_request_count;
  (* mark_debug = "true" *) logic [31:0] dbg_issued_burst_count;
  (* mark_debug = "true" *) logic [31:0] dbg_issued_beat_count;
  (* mark_debug = "true" *) logic [31:0] dbg_useful_count;
  (* mark_debug = "true" *) logic [31:0] dbg_discarded_count;
  (* mark_debug = "true" *) logic [31:0] dbg_merged_count;
  (* mark_debug = "true" *) logic [31:0] dbg_late_miss_count;
  (* mark_debug = "true" *) logic [31:0] dbg_output_count;
  (* mark_debug = "true" *) logic [31:0] dbg_order_error_count;
  (* mark_debug = "true" *) logic [31:0] dbg_reorder_stall_count;
  (* mark_debug = "true" *) logic [STATE_W-1:0] dbg_state;
  (* mark_debug = "true" *) logic [SCENARIO_W-1:0] dbg_scenario;

  assign normalized_mode = (mode_sel > 2'd2) ? 2'd2 : mode_sel;
  assign run_start = (state == ST_START);
  assign run_clear = run_start;
  assign trace_start = run_start;
  assign run_full_burst_enable = (mode_r == 2'd0);
  assign run_merge_enable = (mode_r != 2'd0);
  assign run_reorder_enable = (mode_r == 2'd2);

  assign busy = (state == ST_START) || (state == ST_WAIT);
  assign state_dbg = state;
  assign scenario_dbg = current_scenario;
  assign active_mode_dbg = mode_r;
  assign issued_burst_pulse = burst_valid && burst_ready;
  assign run_complete = trace_done && merge_idle && engine_idle && response_idle &&
                        (output_count >= 32'(TRACE_LEN));

  always_comb begin
    pass_condition = 1'b0;
    unique case (mode_r)
      2'd0: begin
        pass_condition = (input_request_count == 32'(TRACE_LEN)) &&
                         (issued_burst_count == 32'(TRACE_LEN)) &&
                         (issued_beat_count == 32'(TRACE_LEN * MAX_BURST_LEN)) &&
                         (useful_count == 32'(TRACE_LEN)) &&
                         (discarded_count == 32'(TRACE_LEN * (MAX_BURST_LEN - 1))) &&
                         (merged_count == 32'd0) &&
                         (late_miss_count == 32'd0) &&
                         (output_count == 32'(TRACE_LEN)) &&
                         (order_error_count == 32'd0);
      end
      2'd1: begin
        pass_condition = (input_request_count == 32'(TRACE_LEN)) &&
                         (issued_burst_count < 32'(TRACE_LEN)) &&
                         (useful_count == 32'(TRACE_LEN)) &&
                         (discarded_count != 32'd0) &&
                         (merged_count != 32'd0) &&
                         (late_miss_count != 32'd0) &&
                         (output_count == 32'(TRACE_LEN)) &&
                         (order_error_count != 32'd0);
      end
      default: begin
        pass_condition = (input_request_count == 32'(TRACE_LEN)) &&
                         (issued_burst_count < 32'(TRACE_LEN)) &&
                         (useful_count == 32'(TRACE_LEN)) &&
                         (discarded_count != 32'd0) &&
                         (merged_count != 32'd0) &&
                         (late_miss_count != 32'd0) &&
                         (output_count == 32'(TRACE_LEN)) &&
                         (order_error_count == 32'd0) &&
                         (reorder_stall_count != 32'd0);
      end
    endcase
  end

  assign dbg_mode                = mode_r;
  assign dbg_cycle_count         = cycle_count;
  assign dbg_input_request_count = input_request_count;
  assign dbg_issued_burst_count  = issued_burst_count;
  assign dbg_issued_beat_count   = issued_beat_count;
  assign dbg_useful_count        = useful_count;
  assign dbg_discarded_count     = discarded_count;
  assign dbg_merged_count        = merged_count;
  assign dbg_late_miss_count     = late_miss_count;
  assign dbg_output_count        = output_count;
  assign dbg_order_error_count   = order_error_count;
  assign dbg_reorder_stall_count = reorder_stall_count;
  assign dbg_state               = state;
  assign dbg_scenario            = current_scenario;

  random_trace_master u_trace_master (
    .clk(clk),
    .rst_n(rst_n),
    .start(trace_start),
    .done(trace_done),
    .req_valid(trace_req_valid),
    .req_ready(trace_req_ready),
    .req(trace_req),
    .accepted_count(trace_accepted_count),
    .current_scenario(current_scenario)
  );

  range_merge_unit u_range_merge (
    .clk(clk),
    .rst_n(rst_n),
    .clear(run_clear),
    .full_burst_enable(run_full_burst_enable),
    .merge_enable(run_merge_enable),
    .trace_done(trace_done),
    .req_valid(trace_req_valid),
    .req_ready(trace_req_ready),
    .req(trace_req),
    .burst_valid(burst_valid),
    .burst_ready(burst_ready),
    .burst_desc(burst_desc),
    .merged_request_pulse(merged_request_pulse),
    .allocated_request_pulse(allocated_request_pulse),
    .late_miss_pulse(late_miss_pulse),
    .merged_scenario(merged_scenario),
    .late_miss_scenario(late_miss_scenario),
    .issued_scenario(issued_scenario),
    .idle(merge_idle),
    .dbg_selected_base(),
    .dbg_selected_len(),
    .dbg_selected_mask()
  );

  bram_read_engine #(
    .BRAM_ADDR_W(BRAM_ADDR_W)
  ) u_bram_read_engine (
    .clk(clk),
    .rst_n(rst_n),
    .burst_valid(burst_valid),
    .burst_ready(burst_ready),
    .burst_desc(burst_desc),
    .bram_en(bram_en),
    .bram_addr(bram_addr),
    .bram_rdata(bram_rdata),
    .rvalid(engine_rvalid),
    .rready(engine_rready),
    .rdata(engine_rdata),
    .ruseful(engine_ruseful),
    .rtag(engine_rtag),
    .rlast(engine_rlast),
    .idle(engine_idle),
    .discarded_beat_pulse(discarded_beat_pulse)
  );

  bram_model #(
    .DATA_W(DATA_W),
    .DEPTH(BRAM_DEPTH),
    .ADDR_W(BRAM_ADDR_W)
  ) u_bram_model (
    .clk(clk),
    .en(bram_en),
    .addr(bram_addr),
    .rdata(bram_rdata)
  );

  response_order_unit u_response_order (
    .clk(clk),
    .rst_n(rst_n),
    .clear(run_clear),
    .reorder_enable(run_reorder_enable),
    .s_valid(engine_rvalid),
    .s_ready(engine_rready),
    .s_data(engine_rdata),
    .s_useful(engine_ruseful),
    .s_tag(engine_rtag),
    .out_pulse(response_out_pulse),
    .out_data(response_out_data),
    .out_tag(response_out_tag),
    .idle(response_idle),
    .reorder_stall_pulse(reorder_stall_pulse)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      mode_r <= 2'd0;
      done <= 1'b0;
      pass <= 1'b0;
      mode_cycle_count <= 32'd0;
      mode_input_request_count <= 32'd0;
      mode_burst_count <= 32'd0;
      mode_issued_beat_count <= 32'd0;
      mode_useful_count <= 32'd0;
      mode_discarded_count <= 32'd0;
      mode_merged_count <= 32'd0;
      mode_late_miss_count <= 32'd0;
      mode_output_count <= 32'd0;
      mode_order_error_count <= 32'd0;
      mode_reorder_stall_count <= 32'd0;
      mode_s0_burst_count <= 32'd0;
      mode_s1_merge_count <= 32'd0;
      mode_s2_merge_count <= 32'd0;
      mode_s3_merge_count <= 32'd0;
      mode_s4_late_miss_count <= 32'd0;
      mode_s5_merge_count <= 32'd0;
      mode_s6_merge_count <= 32'd0;
      mode_s7_merge_count <= 32'd0;
    end else begin
      unique case (state)
        ST_IDLE: begin
          done <= 1'b0;
          pass <= 1'b0;
          if (start) begin
            mode_r <= normalized_mode;
            state <= ST_START;
          end
        end
        ST_START: begin
          state <= ST_WAIT;
        end
        ST_WAIT: begin
          if (run_complete) begin
            mode_cycle_count <= cycle_count;
            mode_input_request_count <= input_request_count;
            mode_burst_count <= issued_burst_count;
            mode_issued_beat_count <= issued_beat_count;
            mode_useful_count <= useful_count;
            mode_discarded_count <= discarded_count;
            mode_merged_count <= merged_count;
            mode_late_miss_count <= late_miss_count;
            mode_output_count <= output_count;
            mode_order_error_count <= order_error_count;
            mode_reorder_stall_count <= reorder_stall_count;
            mode_s0_burst_count <= scenario_burst_count[SC_NO_MERGE];
            mode_s1_merge_count <= scenario_merge_count[SC_LATE_HIT];
            mode_s2_merge_count <= scenario_merge_count[SC_MULTI_HIT];
            mode_s3_merge_count <= scenario_merge_count[SC_BOUNDARY];
            mode_s4_late_miss_count <= scenario_late_miss_count[SC_WINDOW_EXPIRED];
            mode_s5_merge_count <= scenario_merge_count[SC_OVERLAP];
            mode_s6_merge_count <= scenario_merge_count[SC_DENSE_CLUSTER];
            mode_s7_merge_count <= scenario_merge_count[SC_MIXED_SPARSE];
            pass <= pass_condition;
            done <= 1'b1;
            state <= ST_DONE;
          end
        end
        ST_DONE: begin
          if (start) begin
            done <= 1'b0;
            pass <= 1'b0;
            mode_r <= normalized_mode;
            state <= ST_START;
          end
        end
        default: begin
          state <= ST_IDLE;
        end
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cycle_count <= 32'd0;
      input_request_count <= 32'd0;
      issued_burst_count <= 32'd0;
      issued_beat_count <= 32'd0;
      useful_count <= 32'd0;
      discarded_count <= 32'd0;
      merged_count <= 32'd0;
      late_miss_count <= 32'd0;
      output_count <= 32'd0;
      order_error_count <= 32'd0;
      reorder_stall_count <= 32'd0;
      expected_out_tag <= '0;
      for (int i = 0; i < NUM_SCENARIOS; i++) begin
        scenario_input_count[i] <= 32'd0;
        scenario_burst_count[i] <= 32'd0;
        scenario_merge_count[i] <= 32'd0;
        scenario_late_miss_count[i] <= 32'd0;
      end
    end else begin
      if (run_clear) begin
        cycle_count <= 32'd0;
        input_request_count <= 32'd0;
        issued_burst_count <= 32'd0;
        issued_beat_count <= 32'd0;
        useful_count <= 32'd0;
        discarded_count <= 32'd0;
        merged_count <= 32'd0;
        late_miss_count <= 32'd0;
        output_count <= 32'd0;
        order_error_count <= 32'd0;
        reorder_stall_count <= 32'd0;
        expected_out_tag <= '0;
        for (int i = 0; i < NUM_SCENARIOS; i++) begin
          scenario_input_count[i] <= 32'd0;
          scenario_burst_count[i] <= 32'd0;
          scenario_merge_count[i] <= 32'd0;
          scenario_late_miss_count[i] <= 32'd0;
        end
      end else if (state == ST_WAIT) begin
        cycle_count <= cycle_count + 32'd1;

        if (trace_req_valid && trace_req_ready) begin
          input_request_count <= input_request_count + 32'd1;
          scenario_input_count[trace_req.scenario] <= scenario_input_count[trace_req.scenario] + 32'd1;
        end

        if (issued_burst_pulse) begin
          issued_burst_count <= issued_burst_count + 32'd1;
          issued_beat_count <= issued_beat_count + {27'd0, burst_desc.len};
          scenario_burst_count[issued_scenario] <= scenario_burst_count[issued_scenario] + 32'd1;
        end

        if (engine_rvalid && engine_rready && engine_ruseful) begin
          useful_count <= useful_count + 32'd1;
        end

        if (discarded_beat_pulse) begin
          discarded_count <= discarded_count + 32'd1;
        end

        if (merged_request_pulse) begin
          merged_count <= merged_count + 32'd1;
          scenario_merge_count[merged_scenario] <= scenario_merge_count[merged_scenario] + 32'd1;
        end

        if (late_miss_pulse) begin
          late_miss_count <= late_miss_count + 32'd1;
          scenario_late_miss_count[late_miss_scenario] <=
              scenario_late_miss_count[late_miss_scenario] + 32'd1;
        end

        if (response_out_pulse) begin
          output_count <= output_count + 32'd1;
          if (response_out_tag != expected_out_tag) begin
            order_error_count <= order_error_count + 32'd1;
          end
          expected_out_tag <= expected_out_tag + {{(TAG_W-1){1'b0}}, 1'b1};
        end

        if (reorder_stall_pulse) begin
          reorder_stall_count <= reorder_stall_count + 32'd1;
        end
      end
    end
  end

  logic unused_core;
  assign unused_core = ^{
    trace_accepted_count[0],
    allocated_request_pulse,
    engine_rlast,
    response_out_data[0],
    scenario_input_count[0][0]
  };
endmodule
