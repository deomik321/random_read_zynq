// rtl/rrz_pkg.sv
`timescale 1ns/1ps
package rrz_pkg;
  parameter int ADDR_W         = 32;
  parameter int DATA_W         = 32;
  parameter int BEAT_BYTES     = DATA_W / 8;
  parameter int ADDR_LSB       = $clog2(BEAT_BYTES);
  parameter int MAX_BURST_LEN  = 16;
  parameter int TAG_W          = 8;
  parameter int TRACE_LEN      = 40;
  parameter int NUM_SCENARIOS  = 8;
  parameter int WINDOW_ENTRIES = 4;
  parameter int RETIRED_ENTRIES = 4;
  parameter int MERGE_WINDOW_CYCLES = 7;

  localparam int BURST_LEN_W = $clog2(MAX_BURST_LEN + 1);
  localparam int OFFSET_W    = $clog2(MAX_BURST_LEN);
  localparam int SCENARIO_W  = $clog2(NUM_SCENARIOS);
  localparam int TRACE_IDX_W = $clog2(TRACE_LEN + 1);
  localparam int STATE_W     = 4;
  localparam int AGE_W       = 8;

  typedef enum logic [SCENARIO_W-1:0] {
    SC_NO_MERGE       = 3'd0,
    SC_LATE_HIT       = 3'd1,
    SC_MULTI_HIT      = 3'd2,
    SC_BOUNDARY       = 3'd3,
    SC_WINDOW_EXPIRED = 3'd4,
    SC_OVERLAP        = 3'd5,
    SC_DENSE_CLUSTER  = 3'd6,
    SC_MIXED_SPARSE   = 3'd7
  } scenario_t;

  typedef struct packed {
    logic [ADDR_W-1:0] addr;
    logic [7:0]        gap_after;
    scenario_t         scenario;
  } trace_entry_t;

  typedef struct packed {
    logic [ADDR_W-1:0] addr;
    logic [TAG_W-1:0]  tag;
    scenario_t         scenario;
  } read_req_t;

  typedef struct packed {
    logic [ADDR_W-1:0]              base_addr;
    logic [BURST_LEN_W-1:0]         len;
    logic [MAX_BURST_LEN-1:0]       useful_mask;
    logic [TAG_W*MAX_BURST_LEN-1:0] tag_table;
    scenario_t                      scenario;
  } burst_desc_t;
endpackage
