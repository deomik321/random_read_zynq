// rtl/range_merge_unit.sv
`timescale 1ns/1ps
module range_merge_unit (
  input  logic clk,
  input  logic rst_n,

  input  logic clear,
  input  logic full_burst_enable,
  input  logic merge_enable,
  input  logic trace_done,

  input  logic req_valid,
  output logic req_ready,
  input  rrz_pkg::read_req_t req,

  output logic burst_valid,
  input  logic burst_ready,
  output rrz_pkg::burst_desc_t burst_desc,

  output logic merged_request_pulse,
  output logic allocated_request_pulse,
  output logic late_miss_pulse,
  output logic [rrz_pkg::SCENARIO_W-1:0] merged_scenario,
  output logic [rrz_pkg::SCENARIO_W-1:0] late_miss_scenario,
  output logic [rrz_pkg::SCENARIO_W-1:0] issued_scenario,
  output logic idle,

  output logic [rrz_pkg::ADDR_W-1:0] dbg_selected_base,
  output logic [rrz_pkg::BURST_LEN_W-1:0] dbg_selected_len,
  output logic [rrz_pkg::MAX_BURST_LEN-1:0] dbg_selected_mask
);
  import rrz_pkg::*;

  localparam logic [BURST_LEN_W-1:0] ONE_BEAT  = BURST_LEN_W'(1);
  localparam logic [BURST_LEN_W-1:0] FULL_BEAT = BURST_LEN_W'(MAX_BURST_LEN);

  logic [WINDOW_ENTRIES-1:0] valid;
  logic [ADDR_W-1:0] base_addr [WINDOW_ENTRIES];
  logic [BURST_LEN_W-1:0] len [WINDOW_ENTRIES];
  logic [MAX_BURST_LEN-1:0] useful_mask [WINDOW_ENTRIES];
  logic [TAG_W*MAX_BURST_LEN-1:0] tag_table [WINDOW_ENTRIES];
  scenario_t scenario [WINDOW_ENTRIES];
  logic [AGE_W-1:0] age [WINDOW_ENTRIES];

  logic [RETIRED_ENTRIES-1:0] retired_valid;
  logic [ADDR_W-1:0] retired_base [RETIRED_ENTRIES];

  burst_desc_t issue_desc;
  logic issue_valid;

  logic match_found;
  logic [$clog2(WINDOW_ENTRIES)-1:0] match_idx;
  logic [OFFSET_W-1:0] match_offset;
  logic free_found;
  logic [$clog2(WINDOW_ENTRIES)-1:0] free_idx;
  logic issue_found;
  logic [$clog2(WINDOW_ENTRIES)-1:0] issue_idx;
  logic late_miss_found;
  logic [ADDR_W-1:0] delta_window [WINDOW_ENTRIES];
  logic [ADDR_W-1:0] delta_retired [RETIRED_ENTRIES];

  read_req_t decision_req;
  logic decision_valid;
  logic decision_match_found;
  logic [$clog2(WINDOW_ENTRIES)-1:0] decision_match_idx;
  logic [OFFSET_W-1:0] decision_match_offset;
  logic decision_free_found;
  logic [$clog2(WINDOW_ENTRIES)-1:0] decision_free_idx;
  logic decision_late_miss_found;
  logic [MAX_BURST_LEN-1:0] allocated_mask;
  logic [BURST_LEN_W-1:0] allocated_len;

  assign burst_valid = issue_valid;
  assign burst_desc  = issue_desc;
  assign req_ready   = !decision_valid && !issue_valid && !issue_found &&
                       (match_found || free_found);
  assign idle        = (valid == '0) && !issue_valid && !decision_valid;
  assign issued_scenario = issue_desc.scenario;
  assign allocated_mask = {{(MAX_BURST_LEN-1){1'b0}}, 1'b1};
  assign allocated_len = full_burst_enable ? FULL_BEAT : ONE_BEAT;

  always_comb begin
    match_found  = 1'b0;
    match_idx    = '0;
    match_offset = '0;
    for (int i = 0; i < WINDOW_ENTRIES; i++) begin
      delta_window[i] = req.addr - base_addr[i];
      if (merge_enable && req_valid && valid[i] && !match_found) begin
        if ((req.addr >= base_addr[i]) &&
            (delta_window[i] < ADDR_W'(MAX_BURST_LEN * BEAT_BYTES)) &&
            (delta_window[i][ADDR_LSB-1:0] == '0)) begin
          match_found  = 1'b1;
          match_idx    = i[$clog2(WINDOW_ENTRIES)-1:0];
          match_offset = delta_window[i][ADDR_LSB +: OFFSET_W];
        end
      end
    end
  end

  always_comb begin
    free_found = 1'b0;
    free_idx   = '0;
    for (int i = 0; i < WINDOW_ENTRIES; i++) begin
      if (!valid[i] && !free_found) begin
        free_found = 1'b1;
        free_idx   = i[$clog2(WINDOW_ENTRIES)-1:0];
      end
    end
  end

  always_comb begin
    issue_found = 1'b0;
    issue_idx   = '0;
    for (int i = 0; i < WINDOW_ENTRIES; i++) begin
      if (valid[i] && !issue_found) begin
        if (!merge_enable || trace_done || (age[i] >= AGE_W'(MERGE_WINDOW_CYCLES))) begin
          issue_found = 1'b1;
          issue_idx   = i[$clog2(WINDOW_ENTRIES)-1:0];
        end
      end
    end
  end

  always_comb begin
    late_miss_found = 1'b0;
    for (int i = 0; i < RETIRED_ENTRIES; i++) begin
      delta_retired[i] = req.addr - retired_base[i];
      if (merge_enable && req_valid && !match_found && retired_valid[i] && !late_miss_found) begin
        if ((req.addr >= retired_base[i]) &&
            (delta_retired[i] < ADDR_W'(MAX_BURST_LEN * BEAT_BYTES)) &&
            (delta_retired[i][ADDR_LSB-1:0] == '0)) begin
          late_miss_found = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid                   <= '0;
      retired_valid           <= '0;
      issue_valid             <= 1'b0;
      issue_desc              <= '0;
      decision_valid          <= 1'b0;
      decision_req            <= '0;
      decision_match_found    <= 1'b0;
      decision_match_idx      <= '0;
      decision_match_offset   <= '0;
      decision_free_found     <= 1'b0;
      decision_free_idx       <= '0;
      decision_late_miss_found <= 1'b0;
      merged_request_pulse    <= 1'b0;
      allocated_request_pulse <= 1'b0;
      late_miss_pulse         <= 1'b0;
      merged_scenario         <= '0;
      late_miss_scenario      <= '0;
      dbg_selected_base       <= '0;
      dbg_selected_len        <= '0;
      dbg_selected_mask       <= '0;
      for (int i = 0; i < WINDOW_ENTRIES; i++) begin
        base_addr[i]   <= '0;
        len[i]         <= '0;
        useful_mask[i] <= '0;
        tag_table[i]   <= '0;
        scenario[i]    <= SC_NO_MERGE;
        age[i]         <= '0;
      end
      for (int i = 0; i < RETIRED_ENTRIES; i++) begin
        retired_base[i] <= '0;
      end
    end else begin
      merged_request_pulse    <= 1'b0;
      allocated_request_pulse <= 1'b0;
      late_miss_pulse         <= 1'b0;

      if (clear) begin
        valid                   <= '0;
        retired_valid           <= '0;
        issue_valid             <= 1'b0;
        issue_desc              <= '0;
        decision_valid          <= 1'b0;
        decision_req            <= '0;
        decision_match_found    <= 1'b0;
        decision_free_found     <= 1'b0;
        decision_late_miss_found <= 1'b0;
        for (int i = 0; i < WINDOW_ENTRIES; i++) begin
          base_addr[i]   <= '0;
          len[i]         <= '0;
          useful_mask[i] <= '0;
          tag_table[i]   <= '0;
          scenario[i]    <= SC_NO_MERGE;
          age[i]         <= '0;
        end
        for (int i = 0; i < RETIRED_ENTRIES; i++) begin
          retired_base[i] <= '0;
        end
      end else begin
        for (int i = 0; i < WINDOW_ENTRIES; i++) begin
          if (valid[i] && (age[i] != {AGE_W{1'b1}})) begin
            age[i] <= age[i] + {{(AGE_W-1){1'b0}}, 1'b1};
          end
        end

        if (issue_valid && burst_ready) begin
          issue_valid <= 1'b0;
        end

        if (decision_valid) begin
          decision_valid <= 1'b0;
          if (decision_match_found) begin
            useful_mask[decision_match_idx][decision_match_offset] <= 1'b1;
            tag_table[decision_match_idx][decision_match_offset*TAG_W +: TAG_W] <= decision_req.tag;
            if ((BURST_LEN_W'(decision_match_offset) + ONE_BEAT) > len[decision_match_idx]) begin
              len[decision_match_idx] <= BURST_LEN_W'(decision_match_offset) + ONE_BEAT;
            end
            merged_request_pulse <= 1'b1;
            merged_scenario      <= decision_req.scenario;
            dbg_selected_base    <= base_addr[decision_match_idx];
            dbg_selected_len     <= BURST_LEN_W'(decision_match_offset) + ONE_BEAT;
            dbg_selected_mask    <= useful_mask[decision_match_idx] |
                                    (allocated_mask << decision_match_offset);
          end else if (decision_free_found) begin
            valid[decision_free_idx]       <= 1'b1;
            base_addr[decision_free_idx]   <= decision_req.addr;
            len[decision_free_idx]         <= allocated_len;
            useful_mask[decision_free_idx] <= allocated_mask;
            tag_table[decision_free_idx]   <= '0;
            tag_table[decision_free_idx][TAG_W-1:0] <= decision_req.tag;
            scenario[decision_free_idx]    <= decision_req.scenario;
            age[decision_free_idx]         <= '0;
            allocated_request_pulse <= 1'b1;
            dbg_selected_base       <= decision_req.addr;
            dbg_selected_len        <= allocated_len;
            dbg_selected_mask       <= allocated_mask;
            if (decision_late_miss_found) begin
              late_miss_pulse    <= 1'b1;
              late_miss_scenario <= decision_req.scenario;
            end
          end
        end else if (!issue_valid && issue_found) begin
          issue_desc.base_addr   <= base_addr[issue_idx];
          issue_desc.len         <= len[issue_idx];
          issue_desc.useful_mask <= useful_mask[issue_idx];
          issue_desc.tag_table   <= tag_table[issue_idx];
          issue_desc.scenario    <= scenario[issue_idx];
          valid[issue_idx]       <= 1'b0;
          issue_valid            <= 1'b1;

          retired_valid <= {retired_valid[RETIRED_ENTRIES-2:0], 1'b1};
          for (int i = RETIRED_ENTRIES-1; i > 0; i--) begin
            retired_base[i] <= retired_base[i-1];
          end
          retired_base[0] <= base_addr[issue_idx];
        end

        if (req_valid && req_ready) begin
          decision_req             <= req;
          decision_valid           <= 1'b1;
          decision_match_found     <= match_found;
          decision_match_idx       <= match_idx;
          decision_match_offset    <= match_offset;
          decision_free_found      <= free_found;
          decision_free_idx        <= free_idx;
          decision_late_miss_found <= late_miss_found;
        end
      end
    end
  end
endmodule
