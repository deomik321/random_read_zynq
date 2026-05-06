# scripts/create_project.tcl
set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file normalize [file join $script_dir ..]]
set proj_name  random_read_zynq

create_project -force $proj_name $proj_dir -part xc7z020clg484-1

if {[llength [get_board_parts -quiet xilinx.com:zc702:part0:*]] > 0} {
  set_property board_part [lindex [get_board_parts -quiet xilinx.com:zc702:part0:*] end] [current_project]
}

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property XPM_LIBRARIES {XPM_CDC} [current_project]

add_files -fileset sources_1 [list \
  [file join $proj_dir rtl rrz_pkg.sv] \
  [file join $proj_dir rtl bram_model.sv] \
  [file join $proj_dir rtl random_trace_master.sv] \
  [file join $proj_dir rtl range_merge_unit.sv] \
  [file join $proj_dir rtl bram_read_engine.sv] \
  [file join $proj_dir rtl response_order_unit.sv] \
  [file join $proj_dir rtl random_read_core.sv] \
  [file join $proj_dir rtl random_read_zynq_top.sv] \
]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1] *.sv]
set_property top random_read_zynq_top [get_filesets sources_1]

add_files -fileset constrs_1 [file join $proj_dir constraints zc702_random_read_zynq.xdc]

add_files -fileset sim_1 [file join $proj_dir tb tb_random_read_zynq.sv]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top tb_random_read_zynq [get_filesets sim_1]

set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FANOUT_LIMIT 64 [get_runs synth_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "random_read_zynq project created at $proj_dir"
