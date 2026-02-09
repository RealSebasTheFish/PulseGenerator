`timescale 1ns/1ps

// ============================================================================
// Updated System Testbench for 50MHz Input Clock
//   - Targets: DE10-Lite / MAX 10 Migration
//   - Clock: 50MHz (20ns period)
//   - Baud: 115200 (BITTIME = 8680 ns)
// ============================================================================

module tb_pulseController_50MHz;

  // --------------------------------------------------------------------------
  // DUT signals
  // --------------------------------------------------------------------------
  reg  clk50   = 0;
  reg  usb_rx  = 1;    // UART idle high [cite: 4]
  reg  trig    = 0;
  
  wire usb_tx;
  wire clkled, startled, trigled, led;
  wire [3:0] channel;

  // --------------------------------------------------------------------------
  // 50 MHz reference clock (20ns period)
  // --------------------------------------------------------------------------
  always #10 clk50 = ~clk50; // #10 toggle = 20ns period 

  // --------------------------------------------------------------------------
  // Instantiate DUT
  // --------------------------------------------------------------------------
  pulseController dut (
    .clk50    (clk50),
    .usb_rx   (usb_rx),
    .usb_tx   (usb_tx),
    .trig     (trig),
    .clkled   (clkled),
    .startled (startled),
    .trigled  (trigled),
    .channel  (channel),
    .led      (led)
  );

  // --------------------------------------------------------------------------
  // UART timing and parameters
  // --------------------------------------------------------------------------
  parameter integer BITTIME = 8680; // ns for 115200 baud [cite: 7, 8]
  
  parameter [7:0] CMD_WR_DELAY = 8'h01; 
  parameter [7:0] CMD_WR_WIDTH = 8'h02; 
  parameter [7:0] CMD_START    = 8'h07; 
  parameter [7:0] CMD_STOP     = 8'h03; 

  // --------------------------------------------------------------------------
  // CRC16-CCITT Helper [cite: 12-17]
  // --------------------------------------------------------------------------
  function [15:0] crc16_ccitt;
    input [15:0] crc_in;
    input [7:0]  data;
    integer j;
    reg [15:0] c;
    begin
      c = crc_in ^ (data << 8);
      for (j = 0; j < 8; j = j + 1)
        if (c[15]) c = (c << 1) ^ 16'h1021;
        else        c = (c << 1);
      crc16_ccitt = c;
    end
  endfunction

  // --------------------------------------------------------------------------
  // UART Send Task (8N1, LSB-first) [cite: 17-21]
  // --------------------------------------------------------------------------
  task uart_send_byte;
    input [7:0] data;
    integer i;
    begin
      usb_rx <= 0; #(BITTIME); // Start bit
      for (i = 0; i < 8; i = i + 1) begin
        usb_rx <= data[i];
        #(BITTIME);
      end
      usb_rx <= 1; #(BITTIME); // Stop bit
    end
  endtask

  // --------------------------------------------------------------------------
  // Framed UART sender [cite: 34-37]
  // --------------------------------------------------------------------------
  task send_uart_frame;
    input [7:0] cmd;
    input [7:0] ch;
    input [7:0] blk;
    input [7:0] data_byte;
    reg [15:0] crc;
    begin
      uart_send_byte(8'h55); // Sync 1
      uart_send_byte(8'hAA); // Sync 2
      uart_send_byte(8'd4);  // Length
      crc = 16'hFFFF;

      uart_send_byte(cmd);       crc = crc16_ccitt(crc, cmd);
      uart_send_byte(ch);        crc = crc16_ccitt(crc, ch);
      uart_send_byte(blk);       crc = crc16_ccitt(crc, blk);
      uart_send_byte(data_byte); crc = crc16_ccitt(crc, data_byte);

      uart_send_byte(crc[7:0]);  // CRC_L
      uart_send_byte(crc[15:8]); // CRC_H
    end
  endtask

  // --------------------------------------------------------------------------
  // Main Stimulus
  // --------------------------------------------------------------------------
  initial begin
    $display("\n=== [PULSE ENGINE 50MHZ FUNCTIONAL TEST] ===");
    
    // Initial State
    usb_rx = 1;
    trig = 0;
    
    // Wait for PLL Lock - Essential for Altera/Intel Simulation
    $display("[TB] Resetting and waiting for PLL Lock...");
    #2000;
    wait(dut.lock2 == 1'b1); 
    $display("[TB] PLL Locked at %0t. Internal clk400/clk100 active.", $time);
    #5000;

    // Step 1: Load Timing Data (Channel 0, Block 0: Delay=0x10, Width=0x08)
    $display("[TB] Programming Delay=0x10, Width=0x08...");
    send_uart_frame(CMD_WR_DELAY, 8'h00, 8'h00, 8'h10);
    #(BITTIME * 12); // Allow frame to finish
    
    send_uart_frame(CMD_WR_WIDTH, 8'h00, 8'h00, 8'h08);
    #(BITTIME * 12);

    // Step 2: Start the Engine [cite: 73, 74]
    $display("[TB] Sending START command...");
    send_uart_frame(CMD_START, 8'h00, 8'h00, 8'h00);
    #(BITTIME * 12);

    // Step 3: Issue Trigger [cite: 75, 76]
    $display("[TB] Triggering Pulse...");
    trig <= 1;
    #100; // Hold trigger for 5 cycles @ 50MHz
    trig <= 0;
    
    // Observe pulse on channel output
    #20000; 
    $display("[TB] Channel bits observed: %b", channel);

    // Step 4: Stop and Verify [cite: 79, 80]
    $display("[TB] Sending STOP command...");
    send_uart_frame(CMD_STOP, 8'h00, 8'h00, 8'h00);
    #(BITTIME * 12);

    $display("[TB] Sending trigger after STOP (Checking for silence)...");
    trig <= 1;
    #100;
    trig <= 0;
    #20000;
    
    if (channel !== 4'b0000)
        $error("[TB] FAIL: Pulse detected after STOP command!");
    else
        $display("[TB] PASS: No activity after STOP.");

    $display("=== [TEST COMPLETE] ===\n");
    $finish;
  end

endmodule