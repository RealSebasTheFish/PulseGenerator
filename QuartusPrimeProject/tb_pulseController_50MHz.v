`timescale 1ns/1ps

// ============================================================================
// System Testbench for 50MHz Input Clock + READBACK TESTS (LEVEL DEBUG VERSION)
//   - Debug signals are LEVELS (stay high while a phase/task is executing)
//   - Includes nested-task visibility: outer stays high while inner is high
// ============================================================================

module tb_pulseController_50MHz;

  // --------------------------------------------------------------------------
  // DUT signals
  // --------------------------------------------------------------------------
  reg  clk50   = 0;
  reg  usb_rx  = 1;    // UART idle high
  reg  trig    = 0;

  wire usb_tx;
  wire clkled, startled, trigled, led;
  wire [3:0] channel;

  // --------------------------------------------------------------------------
  // 50 MHz reference clock (20ns period)
  // --------------------------------------------------------------------------
  always #10 clk50 = ~clk50;

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
  parameter integer BITTIME = 8680; // ns for 115200 baud

  // Commands
  parameter [7:0] CMD_WR_DELAY = 8'h01;
  parameter [7:0] CMD_WR_WIDTH = 8'h02;
  parameter [7:0] CMD_STOP     = 8'h03;
  parameter [7:0] CMD_RD_DELAY = 8'h05;
  parameter [7:0] CMD_RD_WIDTH = 8'h06;
  parameter [7:0] CMD_START    = 8'h07;

  // Responses
  parameter [7:0] ACK  = 8'h06;
  parameter [7:0] NACK = 8'h15;

  integer UART_DEBUG = 1;

  // --------------------------------------------------------------------------
  // TB PHASE DEBUG (LEVELS)
  // --------------------------------------------------------------------------
  reg ph_wait_pll   = 1'b0;
  reg ph_wr_prog    = 1'b0;
  reg ph_rd_verify  = 1'b0;
  reg ph_start_cmd  = 1'b0;
  reg ph_trig       = 1'b0;
  reg ph_stop_cmd   = 1'b0;
  reg ph_post_stop  = 1'b0;
  reg ph_done       = 1'b0;

  // --------------------------------------------------------------------------
  // TB TASK DEBUG (LEVELS) — every task has its own “active” signal
  // --------------------------------------------------------------------------
  reg t_uart_send_byte   = 1'b0;
  reg t_uart_recv_byte   = 1'b0;
  reg t_send_uart_frame  = 1'b0;
  reg t_expect_ack       = 1'b0;
  reg t_read_and_check   = 1'b0;

  // Optional “stack depth” counter to prove nesting order
  integer dbg_depth = 0;

  // --------------------------------------------------------------------------
  // Useful “what just happened” state
  // --------------------------------------------------------------------------
  reg [7:0] dbg_last_tx = 8'h00;
  reg [7:0] dbg_last_rx = 8'h00;
  reg [15:0] dbg_tx_count = 16'd0;
  reg [15:0] dbg_rx_count = 16'd0;

  // --------------------------------------------------------------------------
  // UART RX sampling debug (TB-side)
  // --------------------------------------------------------------------------
  reg        rx_sample_pulse = 1'b0;   // 1ns pulse at each sampling instant
  reg        rx_sample_bit   = 1'b0;   // sampled usb_tx at that instant
  reg [3:0]  rx_sample_idx   = 4'd0;   // 0..7=data bits, 8=stop, 9=mid-start

  task tb_mark_sample;
    input [3:0] idx;
    begin
      rx_sample_idx   = idx;
      rx_sample_bit   = usb_tx;
      rx_sample_pulse = 1'b1;
      #1;
      rx_sample_pulse = 1'b0;
    end
  endtask

  // --------------------------------------------------------------------------
  // CRC16-CCITT Helper (poly=0x1021, init=0xFFFF)
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
  // UART Send Task (8N1, LSB-first) — LEVEL DEBUG
  // --------------------------------------------------------------------------
  task uart_send_byte;
    input [7:0] data;
    integer i;
    begin
      dbg_depth = dbg_depth + 1;
      t_uart_send_byte = 1'b1;

      dbg_last_tx  <= data;
      dbg_tx_count <= dbg_tx_count + 1;

      usb_rx <= 0; #(BITTIME); // Start bit
      for (i = 0; i < 8; i = i + 1) begin
        usb_rx <= data[i];
        #(BITTIME);
      end
      usb_rx <= 1; // Stop bit

      if (UART_DEBUG) $display("[%0t] TB->DUT TX byte = 0x%02X (depth=%0d)", $time, data, dbg_depth);

      t_uart_send_byte = 1'b0;
      dbg_depth = dbg_depth - 1;
    end
  endtask

  // --------------------------------------------------------------------------
  // UART Receive Task (DUT -> TB) — LEVEL DEBUG
  //   - This is still your *current* receiver behavior (no logic changes)
  // --------------------------------------------------------------------------
  task uart_recv_byte;
    output [7:0] data;
    integer i;
    reg [7:0] tmp;
    integer tries;
    reg ok;
    begin
      dbg_depth = dbg_depth + 1;
      t_uart_recv_byte = 1'b1;

      data  = 8'h00;
      tmp   = 8'h00;
      tries = 0;
      ok    = 0;

      while ((tries < 50) && (ok == 0)) begin
        tries = tries + 1;

        // Ensure idle-high before arming
        while (usb_tx !== 1'b1) #(BITTIME/10);

        // Wait for falling edge (start bit)
        @(negedge usb_tx);

        // Mid-start confirm still low
        #(BITTIME/2);
        tb_mark_sample(4'd9);
        if (usb_tx !== 1'b0) begin
          ok = 0;
        end else begin
          #(BITTIME); // center of bit0
          for (i = 0; i < 8; i = i + 1) begin
            tb_mark_sample(i[3:0]);
            tmp[i] = usb_tx;
            #(BITTIME);
          end

          #(BITTIME/2);
          tb_mark_sample(4'd8);
          if (usb_tx !== 1'b1) begin
            ok = 0;
          end else begin
            ok   = 1;
            data = tmp;

            dbg_last_rx  <= data;
            dbg_rx_count <= dbg_rx_count + 1;

            if (UART_DEBUG) $display("[%0t] DUT->TB RX byte = 0x%02X (depth=%0d)", $time, data, dbg_depth);
          end
        end
      end

      if (ok == 0) begin
        $display("[%0t] TB ERROR: uart_recv_byte failed (no valid frame)", $time);
        $fatal;
      end

      t_uart_recv_byte = 1'b0;
      dbg_depth = dbg_depth - 1;
    end
  endtask

  // --------------------------------------------------------------------------
  // Framed UART sender — LEVEL DEBUG
  // --------------------------------------------------------------------------
  task send_uart_frame;
    input [7:0] cmd;
    input [7:0] ch;
    input [7:0] blk;
    input [7:0] data_byte;
    reg [15:0] crc;
    begin
      dbg_depth = dbg_depth + 1;
      t_send_uart_frame = 1'b1;
		#(BITTIME)
      uart_send_byte(8'h55);
		#(BITTIME)
      uart_send_byte(8'hAA);
		#(BITTIME)
      uart_send_byte(8'd4);
		#(BITTIME)

      crc = 16'hFFFF;
      uart_send_byte(cmd);       crc = crc16_ccitt(crc, cmd);
		#(BITTIME)
      uart_send_byte(ch);        crc = crc16_ccitt(crc, ch);
		#(BITTIME)
      uart_send_byte(blk);       crc = crc16_ccitt(crc, blk);
		#(BITTIME)
      uart_send_byte(data_byte); crc = crc16_ccitt(crc, data_byte);
		#(BITTIME)
      uart_send_byte(crc[7:0]);
		#(BITTIME)
      uart_send_byte(crc[15:8]);

      t_send_uart_frame = 1'b0;
      dbg_depth = dbg_depth - 1;
    end
  endtask

  // --------------------------------------------------------------------------
  // Expect ACK — LEVEL DEBUG
  // --------------------------------------------------------------------------
  task expect_ack;
    reg [7:0] b;
    begin
      dbg_depth = dbg_depth + 1;
      t_expect_ack = 1'b1;

      uart_recv_byte(b);

      if (b !== ACK) begin
        if (b === NACK)
          $display("[%0t] TB FAIL: got NACK (0x15)", $time);
        else
          $display("[%0t] TB FAIL: expected ACK (0x06), got 0x%02X", $time, b);
        $fatal;
      end

      t_expect_ack = 1'b0;
      dbg_depth = dbg_depth - 1;
    end
  endtask

  // --------------------------------------------------------------------------
  // Readback helper — LEVEL DEBUG
  // --------------------------------------------------------------------------
  task read_and_check;
    input [7:0] cmd;
    input [7:0] ch;
    input [7:0] blk;
    input [7:0] expected;
    reg   [7:0] b;
    begin
      dbg_depth = dbg_depth + 1;
      t_read_and_check = 1'b1;

      send_uart_frame(cmd, ch, blk, 8'h00);
      expect_ack();
      uart_recv_byte(b);

      if (b !== expected) begin
        $display("[%0t] TB FAIL: READ cmd=0x%02X ch=%0d blk=%0d exp=0x%02X got=0x%02X",
                 $time, cmd, ch, blk, expected, b);
        $fatal;
      end else begin
        $display("[%0t] TB PASS: READ cmd=0x%02X ch=%0d blk=%0d -> 0x%02X",
                 $time, cmd, ch, blk, b);
      end

      t_read_and_check = 1'b0;
      dbg_depth = dbg_depth - 1;
    end
  endtask

  // --------------------------------------------------------------------------
  // Main Stimulus (PHASE LEVELS)
  // --------------------------------------------------------------------------
  initial begin
    $display("\n=== [PULSE ENGINE 50MHZ FUNCTIONAL TEST + READBACK] ===");

    // Init debug
    ph_wait_pll  = 0; ph_wr_prog   = 0; ph_rd_verify = 0; ph_start_cmd = 0;
    ph_trig      = 0; ph_stop_cmd  = 0; ph_post_stop = 0; ph_done      = 0;

    // Initial State
    usb_rx = 1;
    trig   = 0;

    // WAIT_PLL phase
    ph_wait_pll = 1'b1;
    $display("[TB] Resetting and waiting for PLL Lock...");
    #2000;
    wait(dut.lock2 == 1'b1);
    $display("[TB] PLL Locked at %0t. Internal clk400/clk100 active.", $time);
    #5000;
    ph_wait_pll = 1'b0;

    // WR_PROG phase
    ph_wr_prog = 1'b1;
    $display("[TB] Programming CH0 BLK0 Delay=0x10, Width=0x08...");
    send_uart_frame(CMD_WR_DELAY, 8'h00, 8'h00, 8'h10);
    expect_ack();

    send_uart_frame(CMD_WR_WIDTH, 8'h00, 8'h00, 8'h08);
    expect_ack();
    ph_wr_prog = 1'b0;

    // RD_VERIFY phase
    ph_rd_verify = 1'b1;
    $display("[TB] Readback verify CH0 BLK0...");
    read_and_check(CMD_RD_DELAY, 8'h00, 8'h00, 8'h10);
    read_and_check(CMD_RD_WIDTH, 8'h00, 8'h00, 8'h08);
    ph_rd_verify = 1'b0;

    // START phase
    ph_start_cmd = 1'b1;
    $display("[TB] Sending START command...");
    send_uart_frame(CMD_START, 8'h00, 8'h00, 8'h00);
    expect_ack();
    ph_start_cmd = 1'b0;

    // TRIG phase
    ph_trig = 1'b1;
    $display("[TB] Triggering Pulse...");
    trig <= 1; #100; trig <= 0;
    #20000;
    $display("[TB] Channel bits observed: %b", channel);
    ph_trig = 1'b0;

    // STOP phase
    ph_stop_cmd = 1'b1;
    $display("[TB] Sending STOP command...");
    send_uart_frame(CMD_STOP, 8'h00, 8'h00, 8'h00);
    expect_ack();
    ph_stop_cmd = 1'b0;

    // POST_STOP phase
    ph_post_stop = 1'b1;
    $display("[TB] Sending trigger after STOP (Checking for silence)...");
    trig <= 1; #100; trig <= 0;
    #20000;

    if (channel !== 4'b0000)
      $error("[TB] FAIL: Pulse detected after STOP command!");
    else
      $display("[TB] PASS: No activity after STOP.");

    ph_post_stop = 1'b0;

    // DONE
    ph_done = 1'b1;
    $display("=== [TEST COMPLETE] ===\n");
    $finish;
  end

endmodule
