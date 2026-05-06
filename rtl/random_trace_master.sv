// rtl/random_trace_master.sv
`timescale 1ns/1ps
module random_trace_master (
  input  logic clk,
  input  logic rst_n,

  input  logic start,
  output logic done,

  output logic req_valid,
  input  logic req_ready,
  output rrz_pkg::read_req_t req,

  output logic [31:0] accepted_count,
  output logic [rrz_pkg::SCENARIO_W-1:0] current_scenario
);
  import rrz_pkg::*;

  logic running;
  logic [TRACE_IDX_W-1:0] trace_idx;
  logic [7:0] gap_count;
  logic [TAG_W-1:0] tag_counter;
  trace_entry_t current_entry;

  read_req_t req_r;
  logic req_valid_r;
  logic [7:0] req_gap_after_r;
  logic req_last_r;
  logic load_req;
  logic accept_req;

  function automatic trace_entry_t trace_at(input logic [TRACE_IDX_W-1:0] idx);
    trace_entry_t t;
    begin
      t = '0;
      unique case (idx)
        // Scenario 0: no merge
        0:  t = '{32'h0000_0000, 8'd1, SC_NO_MERGE};
        1:  t = '{32'h0000_0100, 8'd1, SC_NO_MERGE};
        2:  t = '{32'h0000_0200, 8'd1, SC_NO_MERGE};
        3:  t = '{32'h0000_0300, 8'd2, SC_NO_MERGE};

        // Scenario 1: A-B-C late hit
        4:  t = '{32'h0000_1000, 8'd1, SC_LATE_HIT};
        5:  t = '{32'h0000_1080, 8'd1, SC_LATE_HIT};
        6:  t = '{32'h0000_103C, 8'd2, SC_LATE_HIT};

        // Scenario 2: one base, multiple hits
        7:  t = '{32'h0000_2000, 8'd1, SC_MULTI_HIT};
        8:  t = '{32'h0000_2100, 8'd1, SC_MULTI_HIT};
        9:  t = '{32'h0000_2010, 8'd1, SC_MULTI_HIT};
        10: t = '{32'h0000_2020, 8'd1, SC_MULTI_HIT};
        11: t = '{32'h0000_203C, 8'd2, SC_MULTI_HIT};

        // Scenario 3: 16-beat boundary
        12: t = '{32'h0000_3000, 8'd1, SC_BOUNDARY};
        13: t = '{32'h0000_303C, 8'd1, SC_BOUNDARY};
        14: t = '{32'h0000_3040, 8'd1, SC_BOUNDARY};
        15: t = '{32'h0000_3080, 8'd2, SC_BOUNDARY};

        // Scenario 4: mergeable address after window expiration
        16: t = '{32'h0000_4000, 8'd9, SC_WINDOW_EXPIRED};
        17: t = '{32'h0000_4100, 8'd1, SC_WINDOW_EXPIRED};
        18: t = '{32'h0000_403C, 8'd2, SC_WINDOW_EXPIRED};

        // Scenario 5: overlapping candidates
        19: t = '{32'h0000_5010, 8'd1, SC_OVERLAP};
        20: t = '{32'h0000_5000, 8'd1, SC_OVERLAP};
        21: t = '{32'h0000_503C, 8'd2, SC_OVERLAP};

        // Scenario 6: dense random cluster
        22: t = '{32'h0000_6008, 8'd1, SC_DENSE_CLUSTER};
        23: t = '{32'h0000_6000, 8'd1, SC_DENSE_CLUSTER};
        24: t = '{32'h0000_603C, 8'd1, SC_DENSE_CLUSTER};
        25: t = '{32'h0000_6010, 8'd1, SC_DENSE_CLUSTER};
        26: t = '{32'h0000_602C, 8'd1, SC_DENSE_CLUSTER};
        27: t = '{32'h0000_6070, 8'd1, SC_DENSE_CLUSTER};
        28: t = '{32'h0000_6040, 8'd1, SC_DENSE_CLUSTER};
        29: t = '{32'h0000_6004, 8'd2, SC_DENSE_CLUSTER};

        // Scenario 7: mixed sparse
        30: t = '{32'h0000_7000, 8'd1, SC_MIXED_SPARSE};
        31: t = '{32'h0000_7044, 8'd1, SC_MIXED_SPARSE};
        32: t = '{32'h0000_7038, 8'd1, SC_MIXED_SPARSE};
        33: t = '{32'h0000_7200, 8'd1, SC_MIXED_SPARSE};
        34: t = '{32'h0000_720C, 8'd1, SC_MIXED_SPARSE};
        35: t = '{32'h0000_7300, 8'd1, SC_MIXED_SPARSE};
        36: t = '{32'h0000_733C, 8'd1, SC_MIXED_SPARSE};
        37: t = '{32'h0000_7340, 8'd1, SC_MIXED_SPARSE};
        38: t = '{32'h0000_7400, 8'd1, SC_MIXED_SPARSE};
        39: t = '{32'h0000_743C, 8'd0, SC_MIXED_SPARSE};
        default: t = '0;
      endcase
      trace_at = t;
    end
  endfunction

  assign current_entry = trace_at(trace_idx);
  assign load_req = running && !req_valid_r && (gap_count == 8'd0) &&
                    (trace_idx < TRACE_IDX_W'(TRACE_LEN));
  assign accept_req = req_valid_r && req_ready;
  assign req_valid = req_valid_r;
  assign req = req_r;
  assign current_scenario = req_valid_r ? req_r.scenario : current_entry.scenario;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      running         <= 1'b0;
      trace_idx       <= '0;
      gap_count       <= 8'd0;
      tag_counter     <= '0;
      accepted_count  <= 32'd0;
      done            <= 1'b0;
      req_r           <= '0;
      req_valid_r     <= 1'b0;
      req_gap_after_r <= 8'd0;
      req_last_r      <= 1'b0;
    end else begin
      if (start) begin
        running         <= 1'b1;
        trace_idx       <= '0;
        gap_count       <= 8'd0;
        tag_counter     <= '0;
        accepted_count  <= 32'd0;
        done            <= 1'b0;
        req_r           <= '0;
        req_valid_r     <= 1'b0;
        req_gap_after_r <= 8'd0;
        req_last_r      <= 1'b0;
      end else begin
        if (accept_req) begin
          req_valid_r <= 1'b0;
          accepted_count <= accepted_count + 32'd1;
          tag_counter <= tag_counter + {{(TAG_W-1){1'b0}}, 1'b1};
          gap_count <= req_gap_after_r;
          if (req_last_r) begin
            running <= 1'b0;
            done <= 1'b1;
          end else begin
            trace_idx <= trace_idx + TRACE_IDX_W'(1);
          end
        end else if (running && !req_valid_r && (gap_count != 8'd0)) begin
          gap_count <= gap_count - 8'd1;
        end

        if (load_req) begin
          req_r.addr <= current_entry.addr;
          req_r.tag <= tag_counter;
          req_r.scenario <= current_entry.scenario;
          req_gap_after_r <= current_entry.gap_after;
          req_last_r <= (trace_idx + TRACE_IDX_W'(1) >= TRACE_IDX_W'(TRACE_LEN));
          req_valid_r <= 1'b1;
        end
      end
    end
  end
endmodule
