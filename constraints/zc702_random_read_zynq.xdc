# constraints/zc702_random_read_zynq.xdc
#
# ZC702 / xc7z020clg484-1 constraints.
# SYSCLK_P/N is the 200 MHz differential system clock from the ZC702 board.
# The RTL uses an MMCM to make a 100 MHz internal experiment clock.

set_property PACKAGE_PIN D18 [get_ports SYSCLK_P]
set_property PACKAGE_PIN C19 [get_ports SYSCLK_N]
set_property IOSTANDARD LVDS_25 [get_ports {SYSCLK_P SYSCLK_N}]
set_property DIFF_TERM TRUE [get_ports {SYSCLK_P SYSCLK_N}]
create_clock -name sys_clk_200m -period 5.000 [get_ports SYSCLK_P]

# GPIO_SW_S / GPIO_SW_N and GPIO_DIP_SW0/1 from the ZC702 user I/O.
set_property PACKAGE_PIN F19 [get_ports RESETN]
set_property PACKAGE_PIN G19 [get_ports START_N]
set_property PACKAGE_PIN W6  [get_ports {MODE[0]}]
set_property PACKAGE_PIN W7  [get_ports {MODE[1]}]
set_property IOSTANDARD LVCMOS25 [get_ports {RESETN START_N MODE[*]}]

# User LEDs DS19..DS12.
set_property PACKAGE_PIN E15 [get_ports {LED[0]}]
set_property PACKAGE_PIN D15 [get_ports {LED[1]}]
set_property PACKAGE_PIN W17 [get_ports {LED[2]}]
set_property PACKAGE_PIN W5  [get_ports {LED[3]}]
set_property PACKAGE_PIN V7  [get_ports {LED[4]}]
set_property PACKAGE_PIN W10 [get_ports {LED[5]}]
set_property PACKAGE_PIN P18 [get_ports {LED[6]}]
set_property PACKAGE_PIN P17 [get_ports {LED[7]}]
set_property IOSTANDARD LVCMOS25 [get_ports {LED[*]}]

# Buttons and DIP switches are asynchronous human inputs. RTL synchronizes them.
set_input_delay -clock [get_clocks sys_clk_200m] -max 2.000 [get_ports {RESETN START_N MODE[*]}]
set_input_delay -clock [get_clocks sys_clk_200m] -min 0.000 [get_ports {RESETN START_N MODE[*]}]
set_false_path -from [get_ports {RESETN START_N MODE[*]}]

# The internal reset is asynchronously asserted and synchronously released.
# It is intentionally not a performance path for this experiment.
set rst_sync_q [get_pins -hier -quiet *reset_sync_reg*/Q]
if {[llength $rst_sync_q] > 0} {
  set_false_path -from $rst_sync_q
}

# LEDs are human-visible status pins, not a timed external interface.
set_output_delay -clock [get_clocks sys_clk_200m] -max 2.000 [get_ports {LED[*]}]
set_output_delay -clock [get_clocks sys_clk_200m] -min -0.500 [get_ports {LED[*]}]
set_false_path -to [get_ports {LED[*]}]
