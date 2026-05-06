# scripts/run_impl.tcl
set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file normalize [file join $script_dir ..]]
set xpr_path   [file join $proj_dir random_read_zynq.xpr]

file mkdir [file join $proj_dir reports]

if {![file exists $xpr_path]} {
  source [file join $script_dir create_project.tcl]
} else {
  open_project $xpr_path
}

set_property XPM_LIBRARIES {XPM_CDC} [current_project]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FANOUT_LIMIT 64 [get_runs synth_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]

reset_run synth_1
launch_runs synth_1 -jobs 6
wait_on_run synth_1

open_run synth_1
source [file join $script_dir setup_debug_ila.tcl]
save_constraints

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 6
wait_on_run impl_1

open_run impl_1
report_timing_summary -file [file join $proj_dir reports timing_summary.rpt]
report_drc            -file [file join $proj_dir reports drc.rpt]
report_methodology    -file [file join $proj_dir reports methodology.rpt]
report_utilization    -file [file join $proj_dir reports utilization.rpt]
