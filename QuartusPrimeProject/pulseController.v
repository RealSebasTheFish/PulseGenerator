`timescale 1ns/1ps

module pulseController (
	input  wire        clk50,
	input  wire        rb_clk,
	input  wire        usb_rx,
	output wire        usb_tx,
	input  wire        trig,
	output wire        clkled,
	output wire        startled,
	output wire        trigled,
	output wire [3:0]  channel,
	output wire        led,
	output wire [7:0]  led_arr,
	input  wire        reset_n
);

	localparam [7:0] ACK  = 8'h06;
	localparam [7:0] NACK = 8'h15;

	wire trigerr;

	// Define necessary wires to create PLL clocking logic
	wire clk100, clk200, rb_clk50, rb_lock, pll_lock;
	
	// PLL unit that locks a 50MHz clock to the optional Rubidium 10MHz clock reference [currently unused]
	clk_pll_10_to_50 wiz_1 (
		.areset(~reset_n),
		.inclk0(rb_clk),
		.c0(rb_clk50),
		.locked(rb_lock)
	);
	
	// PLL unit that locks a 200MHz clock and 100MHz clock to the 50MHz clock either from onboard the FPGA or from the first PLL [on board assumed right now]
	clk_pll_50_to_200 wiz_2 (
		.areset(~reset_n),
		.inclk0(clk50),
		.c0(clk100),
		.c1(clk200),
		.locked(pll_lock)
	);

	// Sync any incoming reset signals to the 100MHz clock domain to avoid undefined behavior
	reg [2:0] rst100_sync = 3'b000;
	always @(posedge clk100 or negedge pll_lock) begin
		if (!pll_lock) rst100_sync <= 3'b000;
		else           rst100_sync <= {rst100_sync[1:0], 1'b1};
	end
	wire rst100_n = rst100_sync[2];

	// Sync any incoming reset signals to the 200MHz clock domain to avoid undefined behavior
	wire async_ok_n = reset_n & pll_lock;
	reg [2:0] rst_sync = 3'b000;
	always @(posedge clk200 or negedge async_ok_n)
		if (!async_ok_n) rst_sync <= 3'b000;
		else             rst_sync <= {rst_sync[1:0], 1'b1};

	wire pc_reset_n = rst_sync[2];

	
	// Define registers for external clock reference detection
	reg  [15:0] detect      = 16'd0;
	reg         rb_valid    = 1'b0;
	reg  [1:0]  clock_check = 2'b00;
	
	// System that checks for activity on the external clock input by checking for edges every cycle of the onboard 50MHz clock and asserting rb_valid if activity is detected 
	always @(posedge clk50 or negedge reset_n) begin
		if (!reset_n) begin
			clock_check <= 2'b00;
			detect      <= 16'd0;
			rb_valid    <= 1'b0;
		end else begin
			clock_check <= {clock_check[0], rb_clk};
			if (clock_check[0] ^ clock_check[1]) begin
				detect   <= 16'h000A;
				rb_valid <= 1'b1;
			end else if (detect != 0) begin
				detect <= detect - 1'b1;
			end else begin
				rb_valid <= 1'b0;
			end
		end
	end

	
	// Synchronize incoming trig signals to the 200MHz clock domain to ensure consistency across trials
	reg trig_s1 = 1'b0, trig_s2 = 1'b0;
	always @(posedge clk200 or negedge pc_reset_n)
		if (!pc_reset_n) {trig_s1, trig_s2} <= 2'b00;
		else             {trig_s1, trig_s2} <= {trig, trig_s1};

	wire trig_level_clk = trig_s2;

	
	// Instantiate the uart receiever module that handles collecting bytes from the UART bridge
	wire        rx_valid, tx_ready;
	wire [7:0]  rx_data;
	wire        tx_valid;
	wire [7:0]  tx_data;

	uart #(.CLK_HZ(100_000_000), .BAUD(115_200)) u_uart (
		.clk(clk100), .rst(~reset_n),
		.rx_i(usb_rx), .tx_o(usb_tx),
		.rx_valid(rx_valid), .rx_data(rx_data),
		.tx_valid(tx_valid), .tx_data(tx_data),
		.tx_ready(tx_ready)
	);

	
	// Instantiate the USB command module that constructs processor instructions from the received bytes passed from the UART bridge
	wire        cmd_valid;
	wire [15:0] cmd_instr;
	wire        resp_valid;
	wire [7:0]  resp_data;
	wire        usbled;

	usb_cmd_gateway u_cmd (
		.clk(clk100), .rst(~reset_n),
		.rx_valid(rx_valid), .rx_data(rx_data),
		.tx_ready(tx_ready),
		.resp_valid(resp_valid), .resp_data(resp_data),
		.cmd_valid(cmd_valid), .cmd_instr(cmd_instr),
		.usbled(usbled)
	);
	
	// Generate a cmd_valid_d signal that indicates to the instruction handler when a valid instruction has been fully loaded and parsed into the instruction reigsters from the USB command gateway
	reg cmd_valid_d = 1'b0;
	always @(posedge clk100 or negedge rst100_n)
		if (!rst100_n) cmd_valid_d <= 1'b0;
		else           cmd_valid_d <= cmd_valid;

	wire cmd_fire = cmd_valid & ~cmd_valid_d;

	// The command is passed to a temporary register for syncing to the 200MHz domain where the instruction handler runs
	reg [15:0] ins_uart = 16'h0000;
	always @(posedge clk100 or negedge rst100_n)
		if (!rst100_n) ins_uart <= 16'h0000;
		else if (cmd_fire) ins_uart <= cmd_instr;
		
	// Command is syncronized in a similar way to the trig and reset signals
	reg [15:0] ins_sync1 = 16'h0000, ins_sync2 = 16'h0000;
	always @(posedge clk200 or negedge pc_reset_n)
		if (!pc_reset_n) {ins_sync1, ins_sync2} <= 32'h0;
		else             {ins_sync1, ins_sync2} <= {ins_uart, ins_sync1};

	wire [15:0] ins_clk = ins_sync2;
	
	// A sticky signal is generated to insure it isnt missed if asserted between clock cycles (out of sync)
	reg cmd_tgl = 1'b0;
	always @(posedge clk100 or negedge rst100_n)
		if (!rst100_n) cmd_tgl <= 1'b0;
		else if (cmd_fire) cmd_tgl <= ~cmd_tgl;

	reg [2:0] cmd_tgl_sync = 3'b000;
	always @(posedge clk200 or negedge pc_reset_n)
		if (!pc_reset_n) cmd_tgl_sync <= 3'b000;
		else             cmd_tgl_sync <= {cmd_tgl_sync[1:0], cmd_tgl};

	wire cmd_pulse_200 = cmd_tgl_sync[2] ^ cmd_tgl_sync[1];
	
	// Parse instruction data into semantic wires for processing by the instruction handler
	wire [2:0] opcode_clk = ins_clk[15:13];
	wire [1:0] chan_clk   = ins_clk[12:11];
	wire [2:0] block_clk  = ins_clk[10:8];
	wire [7:0] data_clk   = ins_clk[7:0];
	
	// Some needed output control signals from the instruction handler that are asserted accoridng to the current instruction that is being decoded
	wire [12:0] dec_delay, dec_width;
	wire [1:0]  dec_control;
	wire [3:0]  rw_signal;
	
	// Instruction handler instantiation
	instructionHandler u_ins (
		.opcode(opcode_clk),
		.data({chan_clk, block_clk, data_clk}),
		.delay(dec_delay),
		.width(dec_width),
		.control(dec_control),
		.rw_signal(rw_signal)
	);
	
	// Times an 8 cycle window where the instruction is considered to be active. Important for if the same instruction is sent twice in a row it can be discretely categorized as so 
	reg [3:0] pulse_timer = 4'd0;
	always @(posedge clk200 or negedge pc_reset_n)
		if (!pc_reset_n) pulse_timer <= 0;
		else if (cmd_pulse_200) pulse_timer <= 8;
		else if (pulse_timer != 0) pulse_timer <= pulse_timer - 1;
	
	// Assert control signals only if instruction is active
	wire instr_active = (pulse_timer != 0);
	wire wr_delay_clk = instr_active & rw_signal[0];
	wire wr_width_clk = instr_active & rw_signal[1];
	wire rd_delay_clk = instr_active & rw_signal[2];
	wire rd_width_clk = instr_active & rw_signal[3];

	// This component taks incoming start and stop control signals, and stretches them longer than the 8 cycle instruction active signal would provide.
	// This is vital as the pulseHandler module relies heavily on these signals, and the logic in it may prevent it from immediately acting on the start and stop signals within an 8 cycle window, so a longer pulse width is imperative
	wire stop_cmd_100   = cmd_fire && (cmd_instr[15:13] == 3'b011);
	wire stop_flush_any = stop_cmd_100;

	wire start_evt_200 = cmd_pulse_200 & (opcode_clk == 3'b111);
	wire stop_evt_200  = cmd_pulse_200 & (opcode_clk == 3'b011);

	reg [3:0] start_stretch = 4'd0;
	reg [3:0] stop_stretch  = 4'd0;

	always @(posedge clk200 or negedge pc_reset_n) begin
		if (!pc_reset_n) begin
			start_stretch <= 4'd0;
			stop_stretch  <= 4'd0;
		end else begin
			if (start_evt_200)       start_stretch <= 4'hF;
			else if (start_stretch != 0) start_stretch <= start_stretch - 1;

			if (stop_evt_200)        stop_stretch  <= 4'hF;
			else if (stop_stretch  != 0) stop_stretch  <= stop_stretch  - 1;
		end
	end

	wire start_to_engine = (start_stretch != 0);
	wire stop_to_engine  = (stop_stretch  != 0);

	// Instantiate memory modules to be used by the pulse generator to store its configuration state
	wire [7:0] delay_q, width_q;
	wire eng_read;
	wire [1:0] eng_channelS;
	wire [2:0] eng_blockS;

	// Delay configuration memory
	memory4c u_delays (
		.clk(clk200),
		.dataIn(dec_delay[7:0]),
		.dataOut(delay_q),
		.blockS(eng_read ? eng_blockS : dec_delay[10:8]),
		.channelS(eng_read ? eng_channelS : dec_delay[12:11]),
		.write(wr_delay_clk),
		.read(rd_delay_clk | eng_read),
		.memReset(~pc_reset_n)
	);
	
	// Width configuaration memory
	memory4c u_widths (
		.clk(clk200),
		.dataIn(dec_width[7:0]),
		.dataOut(width_q),
		.blockS(eng_read ? eng_blockS : dec_width[10:8]),
		.channelS(eng_read ? eng_channelS : dec_width[12:11]),
		.write(wr_width_clk),
		.read(rd_width_clk | eng_read),
		.memReset(~pc_reset_n)
	);

	reg rd_delay_d = 1'b0, rd_width_d = 1'b0;
	always @(posedge clk200 or negedge pc_reset_n)
		if (!pc_reset_n) begin
			rd_delay_d <= 1'b0;
			rd_width_d <= 1'b0;
		end else begin
			rd_delay_d <= rd_delay_clk;
			rd_width_d <= rd_width_clk;
		end

	wire rd_delay_fire = rd_delay_clk & ~rd_delay_d;
	wire rd_width_fire = rd_width_clk & ~rd_width_d;

	reg rd_delay_fire_d1 = 1'b0, rd_width_fire_d1 = 1'b0;
	always @(posedge clk200 or negedge pc_reset_n)
		if (!pc_reset_n) begin
			rd_delay_fire_d1 <= 1'b0;
			rd_width_fire_d1 <= 1'b0;
		end else begin
			rd_delay_fire_d1 <= rd_delay_fire;
			rd_width_fire_d1 <= rd_width_fire;
		end

	reg        rb_push_r;
	reg [7:0]  rb_byte_r;
	always @(posedge clk200 or negedge pc_reset_n)
		if (!pc_reset_n) begin
			rb_push_r <= 1'b0;
			rb_byte_r <= 8'h00;
		end else begin
			rb_push_r <= 1'b0;
			if (rd_delay_fire_d1) begin
				rb_byte_r <= delay_q;
				rb_push_r <= 1'b1;
			end else if (rd_width_fire_d1) begin
				rb_byte_r <= width_q;
				rb_push_r <= 1'b1;
			end
		end

	wire rb_push = rb_push_r;
	wire [7:0] rb_byte = rb_byte_r;

	reg        rb_q0_valid = 1'b0, rb_q1_valid = 1'b0;
	reg [7:0]  rb_q0_data  = 8'h00, rb_q1_data  = 8'h00;

	reg [7:0]  rb_xfer_data    = 8'h00;
	reg        rb_req_tgl_200  = 1'b0;
	reg        rb_busy_200     = 1'b0;

	wire rb_ack_tgl_100;

	reg rb_ack_sync1 = 1'b0, rb_ack_sync2 = 1'b0, rb_ack_sync3 = 1'b0;
	wire rb_ack_edge_200 = rb_ack_sync3 ^ rb_ack_sync2;

	always @(posedge clk200 or negedge pc_reset_n) begin
		if (!pc_reset_n) begin
			rb_ack_sync1 <= 1'b0;
			rb_ack_sync2 <= 1'b0;
			rb_ack_sync3 <= 1'b0;
		end else begin
			rb_ack_sync1 <= rb_ack_tgl_100;
			rb_ack_sync2 <= rb_ack_sync1;
			rb_ack_sync3 <= rb_ack_sync2;
		end
	end

	always @(posedge clk200 or negedge pc_reset_n) begin
		if (!pc_reset_n) begin
			rb_q0_valid    <= 1'b0;
			rb_q1_valid    <= 1'b0;
			rb_q0_data     <= 8'h00;
			rb_q1_data     <= 8'h00;
			rb_xfer_data   <= 8'h00;
			rb_req_tgl_200 <= 1'b0;
			rb_busy_200    <= 1'b0;
		end else if (stop_evt_200) begin
			rb_q0_valid    <= 1'b0;
			rb_q1_valid    <= 1'b0;
			rb_busy_200    <= 1'b0;
		end else begin
			if (rb_push) begin
				if (!rb_q0_valid) begin
					rb_q0_valid <= 1'b1;
					rb_q0_data  <= rb_byte;
				end else if (!rb_q1_valid) begin
					rb_q1_valid <= 1'b1;
					rb_q1_data  <= rb_byte;
				end
			end

			if (rb_busy_200 && rb_ack_edge_200) begin
				rb_busy_200 <= 1'b0;
				if (rb_q1_valid) begin
					rb_q0_data  <= rb_q1_data;
					rb_q0_valid <= 1'b1;
					rb_q1_valid <= 1'b0;
				end else begin
					rb_q0_valid <= 1'b0;
				end
			end

			if (!rb_busy_200 && rb_q0_valid) begin
				rb_xfer_data   <= rb_q0_data;
				rb_req_tgl_200 <= ~rb_req_tgl_200;
				rb_busy_200    <= 1'b1;
			end
		end
	end

	wire rb_req_tgl_200_wire = rb_req_tgl_200;

	reg rb_req_sync1 = 1'b0, rb_req_sync2 = 1'b0;
	reg rb_req_seen  = 1'b0;

	always @(posedge clk100 or negedge rst100_n) begin
		if (!rst100_n) begin
			rb_req_sync1 <= 1'b0;
			rb_req_sync2 <= 1'b0;
		end else begin
			rb_req_sync1 <= rb_req_tgl_200_wire;
			rb_req_sync2 <= rb_req_sync1;
		end
	end

	wire rb_req_edge_100 = rb_req_sync2 ^ rb_req_seen;

	reg [7:0] rb_data_sync1 = 8'h00, rb_data_sync2 = 8'h00;
	always @(posedge clk100 or negedge rst100_n) begin
		if (!rst100_n) begin
			rb_data_sync1 <= 8'h00;
			rb_data_sync2 <= 8'h00;
		end else begin
			rb_data_sync1 <= rb_xfer_data;
			rb_data_sync2 <= rb_data_sync1;
		end
	end

	reg rb_pending_req = 1'b0;
	reg rb_ack_tgl_r   = 1'b0;
	assign rb_ack_tgl_100 = rb_ack_tgl_r;

	reg [7:0] txq_mem [0:31];
	reg [5:0] txq_wptr  = 6'd0;
	reg [5:0] txq_rptr  = 6'd0;
	reg [6:0] txq_count = 7'd0;

	wire txq_empty = (txq_count == 0);
	wire txq_full  = (txq_count == 32);

	reg [3:0] resp_pending = 4'd0;
	reg       ack_inflight = 1'b0;
	reg       ack_waiting  = 1'b0;

	reg       tx_valid_r = 1'b0;
	reg [7:0] tx_data_r  = 8'h00;

	assign tx_valid = tx_valid_r;
	assign tx_data  = tx_data_r;

	reg resp_valid_d = 1'b0;
	always @(posedge clk100 or negedge rst100_n)
		if (!rst100_n) resp_valid_d <= 1'b0;
		else           resp_valid_d <= resp_valid;
	wire resp_fire = resp_valid & ~resp_valid_d;

	wire is_read_cmd_100 = cmd_fire &&
												 ((cmd_instr[15:13] == 3'b101) || (cmd_instr[15:13] == 3'b110));

	always @(posedge clk100 or negedge rst100_n) begin
		if (!rst100_n) begin
			ack_waiting <= 1'b0;
		end else if (stop_flush_any) begin
			ack_waiting <= 1'b0;
		end else begin
			if (is_read_cmd_100)
				ack_waiting <= 1'b1;
			if (tx_ready && !txq_empty && (txq_mem[txq_rptr[4:0]] == ACK))
				ack_waiting <= 1'b0;
		end
	end

	always @(posedge clk100 or negedge rst100_n) begin
		if (!rst100_n) begin
			txq_wptr       <= 0;
			txq_rptr       <= 0;
			txq_count      <= 0;
			resp_pending   <= 0;
			ack_inflight   <= 1'b0;
			tx_valid_r     <= 1'b0;
			tx_data_r      <= 8'h00;
			rb_pending_req <= 1'b0;
			rb_req_seen    <= 1'b0;
			rb_ack_tgl_r   <= 1'b0;
		end else if (stop_flush_any) begin
			txq_wptr       <= 0;
			txq_rptr       <= 0;
			txq_count      <= 0;
			resp_pending   <= 0;
			ack_inflight   <= 1'b0;
			tx_valid_r     <= 1'b0;
			tx_data_r      <= 8'h00;
			rb_pending_req <= 1'b0;
			rb_req_seen    <= rb_req_sync2;
		end else begin
			tx_valid_r <= 1'b0;

			if (rb_req_edge_100)
				rb_pending_req <= 1'b1;

			if (resp_fire && !txq_full) begin
				txq_mem[txq_wptr[4:0]] <= resp_data;
				txq_wptr     <= txq_wptr + 1;
				txq_count    <= txq_count + 1;
				resp_pending <= resp_pending + 1;
				ack_inflight <= 1'b1;
			end

			if (rb_pending_req && !txq_full && !ack_inflight && !ack_waiting) begin
				txq_mem[txq_wptr[4:0]] <= rb_data_sync2;
				txq_wptr       <= txq_wptr + 1;
				txq_count      <= txq_count + 1;
				rb_ack_tgl_r   <= ~rb_ack_tgl_r;
				rb_pending_req <= 1'b0;
				rb_req_seen    <= rb_req_sync2;
			end

			if (tx_ready && !txq_empty) begin
				tx_data_r  <= txq_mem[txq_rptr[4:0]];
				tx_valid_r <= 1'b1;
				if (txq_mem[txq_rptr[4:0]] == ACK)
					ack_inflight <= 1'b0;
				txq_rptr  <= txq_rptr + 1;
				txq_count <= txq_count - 1;
				if (resp_pending != 0)
					resp_pending <= resp_pending - 1;
			end
		end
	end

	wire [7:0] ph_dbg;

	pulseHandler u_pc (
		.clk(clk200),
		.reset_n(pc_reset_n),
		.mem_read(eng_read),
		.mem_channelS(eng_channelS),
		.mem_blockS(eng_blockS),
		.delay_byte(delay_q),
		.width_byte(width_q),
		.start(start_to_engine),
		.stop (stop_to_engine),
		.trig(trig_level_clk),
		.channel(channel),
		.listening(startled),
		.led(trigerr),
		.testphase(ph_dbg)
	);

	
	assign clkled  = 1'b0;
	assign trigled = trigerr;
	
	// DEBUG SIGNALS [not necessary to assign]
	assign led_arr[0] = cmd_valid;
	assign led_arr[1] = cmd_pulse_200;
	assign led_arr[2] = instr_active;
	assign led_arr[3] = start_to_engine;
	assign led_arr[4] = startled;
	assign led_arr[5] = stop_to_engine;
	assign led_arr[6] = pll_lock;
	assign led_arr[7] = rb_valid;

endmodule