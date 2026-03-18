transcript on
if ![file isdirectory verilog_libs] {
	file mkdir verilog_libs
}

vlib verilog_libs/altera_ver
vmap altera_ver ./verilog_libs/altera_ver
vlog -vlog01compat -work altera_ver {c:/intelfpga_lite/22.1std/quartus/eda/sim_lib/altera_primitives.v}

vlib verilog_libs/lpm_ver
vmap lpm_ver ./verilog_libs/lpm_ver
vlog -vlog01compat -work lpm_ver {c:/intelfpga_lite/22.1std/quartus/eda/sim_lib/220model.v}

vlib verilog_libs/sgate_ver
vmap sgate_ver ./verilog_libs/sgate_ver
vlog -vlog01compat -work sgate_ver {c:/intelfpga_lite/22.1std/quartus/eda/sim_lib/sgate.v}

vlib verilog_libs/altera_mf_ver
vmap altera_mf_ver ./verilog_libs/altera_mf_ver
vlog -vlog01compat -work altera_mf_ver {c:/intelfpga_lite/22.1std/quartus/eda/sim_lib/altera_mf.v}

vlib verilog_libs/altera_lnsim_ver
vmap altera_lnsim_ver ./verilog_libs/altera_lnsim_ver
vlog -sv -work altera_lnsim_ver {c:/intelfpga_lite/22.1std/quartus/eda/sim_lib/altera_lnsim.sv}

vlib verilog_libs/fiftyfivenm_ver
vmap fiftyfivenm_ver ./verilog_libs/fiftyfivenm_ver
vlog -vlog01compat -work fiftyfivenm_ver {c:/intelfpga_lite/22.1std/quartus/eda/sim_lib/fiftyfivenm_atoms.v}
vlog -vlog01compat -work fiftyfivenm_ver {c:/intelfpga_lite/22.1std/quartus/eda/sim_lib/mentor/fiftyfivenm_atoms_ncrypt.v}

if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/deMux.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/instructionHandler.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/mux.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/pulseController.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/pulseHandler.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/storage.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/uart.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/usb_cmd_gateway.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/clk_pll_50_to_400.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/clk_pll_10_to_50.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/db {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/db/clk_pll_10_to_50_altpll.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/db {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/db/clk_pll_50_to_400_altpll.v}
vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/memory.v}

vlog -vlog01compat -work work +incdir+C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject {C:/Users/sebas/Downloads/PulseGenerator-main/PulseGenerator-main/QuartusPrimeProject/tb_pulseController_50MHz.v}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L fiftyfivenm_ver -L rtl_work -L work -voptargs="+acc"  tb_pulseController_50MHz

add wave *
view structure
view signals
run -all
