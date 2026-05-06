# scripts/setup_debug_ila.tcl
#
# Run after synthesis:
#   open_run synth_1
#   source scripts/setup_debug_ila.tcl
#   save_constraints

set dbg_nets [lsort -dictionary [get_nets -hier -filter {MARK_DEBUG == 1}]]
if {[llength $dbg_nets] == 0} {
  puts "No MARK_DEBUG nets found. Run synthesis first."
  return
}

set clk_pins [get_pins -hier -quiet *u_sysclk_bufg/O]
set clk_nets [get_nets -hier -quiet -of_objects $clk_pins]
if {[llength $clk_nets] == 0} {
  puts "Could not find the internal BUFG clock. Use GUI Set Up Debug if needed."
  return
}
set clk_net [lindex $clk_nets 0]

if {[llength [get_debug_cores u_ila_random_read_zynq]] == 0} {
  create_debug_core u_ila_random_read_zynq ila
}

set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_random_read_zynq]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_random_read_zynq]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_random_read_zynq]

connect_debug_port u_ila_random_read_zynq/clk $clk_net

if {[llength [get_debug_ports u_ila_random_read_zynq/probe0]] == 0} {
  create_debug_port u_ila_random_read_zynq probe
}

set_property PORT_WIDTH [llength $dbg_nets] [get_debug_ports u_ila_random_read_zynq/probe0]
connect_debug_port u_ila_random_read_zynq/probe0 $dbg_nets

puts "Connected [llength $dbg_nets] MARK_DEBUG nets to u_ila_random_read_zynq."
