// rtl/bram_read_engine.sv
`timescale 1ns/1ps
module bram_read_engine #(
  parameter int BRAM_ADDR_W = 12
) (
  input  logic clk,
  input  logic rst_n,

  input  logic burst_valid,
  output logic burst_ready,
  input  rrz_pkg::burst_desc_t burst_desc,

  output logic bram_en,
  output logic [BRAM_ADDR_W-1:0] bram_addr,
  input  logic [rrz_pkg::DATA_W-1:0] bram_rdata,

  output logic rvalid,
  input  logic rready,
  output logic [rrz_pkg::DATA_W-1:0] rdata,
  output logic ruseful,
  output logic [rrz_pkg::TAG_W-1:0] rtag,
  output logic rlast,
  output logic idle,
  output logic discarded_beat_pulse
);
  import rrz_pkg::*;

  logic active;
  burst_desc_t burst_r;
  logic [ADDR_W-1:0] current_addr;
  logic [BURST_LEN_W-1:0] beats_issued;

  logic bram_en_d;
  logic useful_d;
  logic [TAG_W-1:0] tag_d;
  logic last_d;
  logic rvalid_r;
  logic [DATA_W-1:0] rdata_r;
  logic ruseful_r;
  logic [TAG_W-1:0] rtag_r;
  logic rlast_r;
  logic can_issue;
  logic output_fire;

  assign burst_ready = !active && !rvalid_r && !bram_en_d;
  assign output_fire = rvalid_r && rready;
  assign idle = !active && !rvalid_r && !bram_en_d;
  assign can_issue = active &&
                     (beats_issued < burst_r.len) &&
                     !bram_en_d &&
                     (!rvalid_r || rready);

  assign bram_en   = can_issue;
  assign bram_addr = current_addr[ADDR_LSB +: BRAM_ADDR_W];
  assign rvalid    = rvalid_r;
  assign rdata     = rdata_r;
  assign ruseful   = ruseful_r;
  assign rtag      = rtag_r;
  assign rlast     = rlast_r;
  assign discarded_beat_pulse = output_fire && !ruseful_r;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      active       <= 1'b0;
      burst_r      <= '0;
      current_addr <= '0;
      beats_issued <= '0;
      bram_en_d    <= 1'b0;
      useful_d     <= 1'b0;
      tag_d        <= '0;
      last_d       <= 1'b0;
      rvalid_r     <= 1'b0;
      rdata_r      <= '0;
      ruseful_r    <= 1'b0;
      rtag_r       <= '0;
      rlast_r      <= 1'b0;
    end else begin
      if (output_fire) begin
        rvalid_r <= 1'b0;
        if (rlast_r) begin
          active <= 1'b0;
        end
      end

      if (bram_en_d) begin
        rvalid_r  <= 1'b1;
        rdata_r   <= bram_rdata;
        ruseful_r <= useful_d;
        rtag_r    <= tag_d;
        rlast_r   <= last_d;
      end

      if (burst_valid && burst_ready) begin
        active       <= 1'b1;
        burst_r      <= burst_desc;
        current_addr <= burst_desc.base_addr;
        beats_issued <= '0;
      end else if (can_issue) begin
        current_addr <= current_addr + ADDR_W'(BEAT_BYTES);
        beats_issued <= beats_issued + {{(BURST_LEN_W-1){1'b0}}, 1'b1};
      end

      if (can_issue) begin
        useful_d <= burst_r.useful_mask[beats_issued[OFFSET_W-1:0]];
        tag_d    <= burst_r.tag_table[beats_issued[OFFSET_W-1:0]*TAG_W +: TAG_W];
        last_d   <= (beats_issued == (burst_r.len - {{(BURST_LEN_W-1){1'b0}}, 1'b1}));
      end
      bram_en_d <= can_issue;
    end
  end
endmodule
