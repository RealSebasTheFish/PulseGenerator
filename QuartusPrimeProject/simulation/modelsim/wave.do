onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_pulseController_50MHz/dut/clk50
add wave -noupdate /tb_pulseController_50MHz/dut/clk100
add wave -noupdate /tb_pulseController_50MHz/dut/clk400
add wave -noupdate /tb_pulseController_50MHz/dut/usb_rx
add wave -noupdate /tb_pulseController_50MHz/dut/usb_tx
add wave -noupdate /tb_pulseController_50MHz/dut/channel
add wave -noupdate /tb_pulseController_50MHz/dut/u_uart/rx_valid
add wave -noupdate /tb_pulseController_50MHz/dut/u_uart/rx_data
add wave -noupdate /tb_pulseController_50MHz/dut/u_uart/tx_valid
add wave -noupdate /tb_pulseController_50MHz/dut/u_uart/tx_data
add wave -noupdate /tb_pulseController_50MHz/dut/u_ins/opcode
add wave -noupdate /tb_pulseController_50MHz/dut/u_ins/data
add wave -noupdate /tb_pulseController_50MHz/dut/u_ins/delay
add wave -noupdate /tb_pulseController_50MHz/dut/u_ins/width
add wave -noupdate /tb_pulseController_50MHz/dut/u_ins/control
add wave -noupdate /tb_pulseController_50MHz/dut/u_ins/rw_signal
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1073719682 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {4353933312 ps}
