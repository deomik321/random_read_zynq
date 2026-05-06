// rtl/bram_model.sv
`timescale 1ns/1ps
module bram_model #(
  parameter int DATA_W = 32,
  parameter int DEPTH  = 4096,
  parameter int ADDR_W = $clog2(DEPTH)
) (
  input  logic              clk,
  input  logic              en,
  input  logic [ADDR_W-1:0] addr,
  output logic [DATA_W-1:0] rdata
);
  logic [DATA_W-1:0] mem [0:DEPTH-1];

`ifdef SIM
  initial begin : p_init
    int i;
    for (i = 0; i < DEPTH; i++) begin
      mem[i] = DATA_W'(32'hCAFE_0000 + i);
    end
  end
`endif

  always_ff @(posedge clk) begin
    if (en) begin
      rdata <= mem[addr];
    end
  end
endmodule
