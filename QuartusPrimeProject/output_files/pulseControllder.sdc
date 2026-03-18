# ============================================================
# Base input clocks
# ============================================================
create_clock -name clk50  -period 20.000  [get_ports {clk50}]   ;# 50 MHz
create_clock -name rb_clk -period 100.000 [get_ports {rb_clk}]  ;# 10 MHz (edit if different)

# ============================================================
# Let Quartus derive PLL clocks from the IP
# ============================================================
derive_pll_clocks
derive_clock_uncertainty

# ============================================================
# Convenience collections for derived clocks (names from TimeQuest)
# Based on your clock summary:
#  - wiz_2 ... clk[0] = 100 MHz
#  - wiz_2 ... clk[1] = 400 MHz
# ============================================================
set CLK100 [get_clocks {wiz_2|altpll_component|auto_generated|pll1|clk[0]}]
set CLK400 [get_clocks {wiz_2|altpll_component|auto_generated|pll1|clk[1]}]

# ============================================================
# Clock domain relationships
# rb_clk vs clk50 are unrelated sources (and wiz_2 can switch sources),
# so treat them async.
# clk100 vs clk400 are separate PLL outputs; treat them async too
# (you are doing CDC using sync regs / async fifo).
# ============================================================
set_clock_groups -asynchronous -group [get_clocks {clk50}]  -group [get_clocks {rb_clk}]
set_clock_groups -asynchronous -group $CLK100               -group $CLK400

# ============================================================
# I/O: If you don't have board-level timing numbers, do NOT leave unconstrained.
# Easiest safe option: false-path async inputs and non-timed outputs.
# ============================================================
set_false_path -from [get_ports {usb_rx}]
set_false_path -from [get_ports {trig}]

set_false_path -to   [get_ports {usb_tx}]
set_false_path -to   [get_ports {channel[*]}]
set_false_path -to   [get_ports {led}]
set_false_path -to   [get_ports {led_arr[*]}]
set_false_path -to   [get_ports {clkled startled trigled}]