// rtl/response_order_unit.sv
`timescale 1ns/1ps
module response_order_unit (
  input  logic clk,
  input  logic rst_n,

  input  logic clear,
  input  logic reorder_enable,

  input  logic s_valid,
  output logic s_ready,
  input  logic [rrz_pkg::DATA_W-1:0] s_data,
  input  logic s_useful,
  input  logic [rrz_pkg::TAG_W-1:0] s_tag,

  output logic out_pulse,
  output logic [rrz_pkg::DATA_W-1:0] out_data,
  output logic [rrz_pkg::TAG_W-1:0] out_tag,

  output logic idle,
  output logic reorder_stall_pulse
);
  import rrz_pkg::*;

  logic [TRACE_LEN-1:0] valid_by_tag;
  logic [DATA_W-1:0] data_by_tag [TRACE_LEN];
  logic [TAG_W-1:0] next_tag;
  logic any_buffered;

  assign s_ready = 1'b1;
  assign any_buffered = |valid_by_tag;
  assign idle = !any_buffered;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_by_tag        <= '0;
      next_tag            <= '0;
      out_pulse           <= 1'b0;
      out_data            <= '0;
      out_tag             <= '0;
      reorder_stall_pulse <= 1'b0;
      for (int i = 0; i < TRACE_LEN; i++) begin
        data_by_tag[i] <= '0;
      end
    end else begin
      out_pulse           <= 1'b0;
      reorder_stall_pulse <= 1'b0;

      if (clear) begin
        valid_by_tag <= '0;
        next_tag     <= '0;
      end else if (reorder_enable) begin
        if (s_valid && s_ready && s_useful && (s_tag < TAG_W'(TRACE_LEN))) begin
          data_by_tag[s_tag]  <= s_data;
          valid_by_tag[s_tag] <= 1'b1;
        end

        if ((next_tag < TAG_W'(TRACE_LEN)) && valid_by_tag[next_tag]) begin
          out_pulse              <= 1'b1;
          out_data               <= data_by_tag[next_tag];
          out_tag                <= next_tag;
          valid_by_tag[next_tag] <= 1'b0;
          next_tag               <= next_tag + {{(TAG_W-1){1'b0}}, 1'b1};
        end else if (any_buffered) begin
          reorder_stall_pulse <= 1'b1;
        end
      end else begin
        if (s_valid && s_ready && s_useful) begin
          out_pulse <= 1'b1;
          out_data  <= s_data;
          out_tag   <= s_tag;
        end
      end
    end
  end
endmodule
