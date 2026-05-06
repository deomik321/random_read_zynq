# scripts/run_sim.tcl
set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file normalize [file join $script_dir ..]]
cd $proj_dir

set srcs [list \
  rtl/rrz_pkg.sv \
  rtl/bram_model.sv \
  rtl/random_trace_master.sv \
  rtl/range_merge_unit.sv \
  rtl/bram_read_engine.sv \
  rtl/response_order_unit.sv \
  rtl/random_read_core.sv \
  rtl/random_read_zynq_top.sv \
  tb/tb_random_read_zynq.sv \
]

exec xvlog -sv -d SIM {*}$srcs
exec xelab tb_random_read_zynq -s tb_random_read_zynq_behav
exec xsim tb_random_read_zynq_behav -runall
