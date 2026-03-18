`timescale 1ns/1ps

module pulseHandler #(
    parameter integer CHANNELS     = 4,
    parameter integer BYTES_PER_CH = 8
)(
    input  wire                   clk,
    input  wire                   reset_n,

    output reg                    mem_read,
    output reg  [1:0]             mem_channelS,
    output reg  [2:0]             mem_blockS,

    input  wire [7:0]             delay_byte,
    input  wire [7:0]             width_byte,

    input  wire                   start,
    input  wire                   stop,
    input  wire                   trig,

    output reg  [CHANNELS-1:0]    channel,
    output reg                    led,
    output reg                    ready,
    output reg                    listening,
    output wire [7:0]             testphase
);

    reg [7:0] delay_byte_r, width_byte_r;

    localparam [2:0]
        S_IDLE      = 3'd0,
        S_LOAD_SET  = 3'd1,
        S_LOAD_WAIT = 3'd2,
        S_LOAD_CAP  = 3'd3,
        S_ARMED     = 3'd4,
        S_RUN       = 3'd5;

    reg [2:0] state, nstate;
    integer ch, i;

    reg start_d, stop_d;
    wire start_rise = start & ~start_d;
    wire stop_rise  = stop  & ~stop_d;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            start_d <= 1'b0;
            stop_d  <= 1'b0;
        end else begin
            start_d <= start;
            stop_d  <= stop;
        end
    end

    reg trig_q, trig_qq;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            trig_q  <= 1'b0;
            trig_qq <= 1'b0;
        end else begin
            trig_q  <= trig;
            trig_qq <= trig_q;
        end
    end

    wire trig_rise = trig_q & ~trig_qq;
    wire trig_fall = ~trig_q & trig_qq;

    wire invalid_trig = trig_rise && (state == S_RUN);

    reg trig_rearm;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            trig_rearm <= 1'b1;
        else if (trig_fall)
            trig_rearm <= 1'b1;
        else if (state == S_ARMED && trig_rise)
            trig_rearm <= 1'b0;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            led <= 1'b0;
        else if (stop_rise)
            led <= 1'b0;
        else if (invalid_trig)
            led <= 1'b1;
        else if (trig_rise)
            led <= 1'b0;
    end

    reg [7:0] delay_init_b [0:CHANNELS-1][0:BYTES_PER_CH-1];
    reg [7:0] width_init_b [0:CHANNELS-1][0:BYTES_PER_CH-1];

    reg [63:0] delay_cnt  [0:CHANNELS-1];
    reg [63:0] width_cnt  [0:CHANNELS-1];
    reg [1:0]  phase      [0:CHANNELS-1];

    reg        armed_mode, running;
    reg [1:0]  ch_iter;
    reg [2:0]  blk_iter;

    // small registered flags captured at trigger-time (avoids exporting large amounts)
    reg ch0_delay_any, ch0_width_any;


    reg all_done;
    always @* begin
        all_done = 1'b1;
        for (i = 0; i < CHANNELS; i = i + 1)
            if (phase[i] != 2'd2)
                all_done = 1'b0;
    end


    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            armed_mode <= 1'b0;
        else if (stop_rise)
            armed_mode <= 1'b0;
        else if (start_rise)
            armed_mode <= 1'b1;
    end

    wire valid_trig_in_armed =
        (state == S_ARMED) &&
        armed_mode &&
        trig_rearm &&
        (trig_rise || (trig_q && !running));

    always @* begin
        nstate = state;
        case (state)
            S_IDLE:
                if (armed_mode) nstate = S_LOAD_SET;

            S_LOAD_SET:
                nstate = S_LOAD_WAIT;

            S_LOAD_WAIT:
                nstate = S_LOAD_CAP;

            S_LOAD_CAP:
                if (ch_iter == 2'd3 && blk_iter == 3'd7)
                    nstate = S_ARMED;
                else
                    nstate = S_LOAD_SET;

            S_ARMED:
                if (stop_rise)
                    nstate = S_IDLE;
                else if (valid_trig_in_armed)
                    nstate = S_RUN;

            S_RUN:
                if (stop_rise)
                    nstate = S_IDLE;
                else if (all_done)
                    nstate = armed_mode ? S_ARMED : S_IDLE;

            default:
                nstate = S_IDLE;
        endcase
    end

    function automatic [63:0] pack8;
        input [7:0] b0, b1, b2, b3, b4, b5, b6, b7;
        begin
            pack8 = {b7,b6,b5,b4,b3,b2,b1,b0};
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state     <= S_IDLE;
            running   <= 1'b0;
            channel   <= {CHANNELS{1'b0}};
            ready     <= 1'b0;
            listening <= 1'b0;

            mem_read     <= 1'b0;
            mem_channelS <= 2'd0;
            mem_blockS   <= 3'd0;
            ch_iter      <= 2'd0;
            blk_iter     <= 3'd0;

            delay_byte_r <= 8'h00;
            width_byte_r <= 8'h00;

            ch0_delay_any <= 1'b0;
            ch0_width_any <= 1'b0;

            for (i = 0; i < CHANNELS; i = i + 1) begin
                delay_cnt[i] <= 64'd0;
                width_cnt[i] <= 64'd0;
                phase[i]     <= 2'd0;
            end

            for (i = 0; i < CHANNELS; i = i + 1) begin : RST_INIT
                integer k;
                for (k = 0; k < BYTES_PER_CH; k = k + 1) begin
                    delay_init_b[i][k] <= 8'h00;
                    width_init_b[i][k] <= 8'h00;
                end
            end

        end else begin
            state <= nstate;
            ready <= (state == S_ARMED);

            case (state)
                S_IDLE: begin
                    running    <= 1'b0;
                    listening  <= 1'b0;
                    channel    <= {CHANNELS{1'b0}};
                    mem_read   <= 1'b0;
                    ch_iter    <= 2'd0;
                    blk_iter   <= 3'd0;

                    // clear captured flags on STOP/IDLE
                    ch0_delay_any <= 1'b0;
                    ch0_width_any <= 1'b0;
                end

                S_LOAD_SET: begin
                    mem_channelS <= ch_iter;
                    mem_blockS   <= blk_iter;
                    mem_read     <= 1'b1;
                end

                S_LOAD_WAIT: begin
                    mem_read      <= 1'b0;
                    delay_byte_r  <= delay_byte;
                    width_byte_r  <= width_byte;
                end

                S_LOAD_CAP: begin
                    delay_init_b[mem_channelS][mem_blockS] <= delay_byte_r;
                    width_init_b[mem_channelS][mem_blockS] <= width_byte_r;

                    if (blk_iter == 3'd7) begin
                        blk_iter <= 3'd0;
                        ch_iter  <= (ch_iter == 2'd3) ? 2'd3 : (ch_iter + 2'd1);
                    end else begin
                        blk_iter <= blk_iter + 3'd1;
                    end
                end

                S_ARMED: begin
                    running    <= 1'b0;
                    listening  <= 1'b1;
                    channel    <= {CHANNELS{1'b0}};
                    mem_read   <= 1'b0;

                    if (valid_trig_in_armed) begin
                        // Capture whether channel 0 has any nonzero delay/width bytes.
                        ch0_delay_any <= ( (delay_init_b[0][0]|delay_init_b[0][1]|delay_init_b[0][2]|delay_init_b[0][3]|
                                            delay_init_b[0][4]|delay_init_b[0][5]|delay_init_b[0][6]|delay_init_b[0][7]) != 8'h00 );
                        ch0_width_any <= ( (width_init_b[0][0]|width_init_b[0][1]|width_init_b[0][2]|width_init_b[0][3]|
                                            width_init_b[0][4]|width_init_b[0][5]|width_init_b[0][6]|width_init_b[0][7]) != 8'h00 );

                        for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                            delay_cnt[ch] <= pack8(
                                delay_init_b[ch][0], delay_init_b[ch][1], delay_init_b[ch][2], delay_init_b[ch][3],
                                delay_init_b[ch][4], delay_init_b[ch][5], delay_init_b[ch][6], delay_init_b[ch][7]
                            );
                            width_cnt[ch] <= pack8(
                                width_init_b[ch][0], width_init_b[ch][1], width_init_b[ch][2], width_init_b[ch][3],
                                width_init_b[ch][4], width_init_b[ch][5], width_init_b[ch][6], width_init_b[ch][7]
                            );

                            if ((delay_init_b[ch][0]|delay_init_b[ch][1]|delay_init_b[ch][2]|delay_init_b[ch][3]|
                                 delay_init_b[ch][4]|delay_init_b[ch][5]|delay_init_b[ch][6]|delay_init_b[ch][7]) == 8'h00 &&
                                (width_init_b[ch][0]|width_init_b[ch][1]|width_init_b[ch][2]|width_init_b[ch][3]|
                                 width_init_b[ch][4]|width_init_b[ch][5]|width_init_b[ch][6]|width_init_b[ch][7]) == 8'h00) begin
                                phase[ch]   <= 2'd2;
                                channel[ch] <= 1'b0;
                            end else if ((delay_init_b[ch][0]|delay_init_b[ch][1]|delay_init_b[ch][2]|delay_init_b[ch][3]|
                                          delay_init_b[ch][4]|delay_init_b[ch][5]|delay_init_b[ch][6]|delay_init_b[ch][7]) == 8'h00) begin
                                phase[ch]   <= 2'd1;
                                channel[ch] <= 1'b1;
                            end else begin
                                phase[ch]   <= 2'd0;
                                channel[ch] <= 1'b0;
                            end
                        end
                    end
                end

                S_RUN: begin
                    running <= 1'b1;
                    for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                        case (phase[ch])
                            2'd0: begin
                                if (delay_cnt[ch] != 0)
                                    delay_cnt[ch] <= delay_cnt[ch] - 1;
                                else begin
                                    phase[ch]   <= (width_cnt[ch] == 0) ? 2'd2 : 2'd1;
                                    channel[ch] <= (width_cnt[ch] != 0);
                                end
                            end
                            2'd1: begin
                                if (width_cnt[ch] != 0)
                                    width_cnt[ch] <= width_cnt[ch] - 1;
                                else begin
                                    channel[ch] <= 1'b0;
                                    phase[ch]   <= 2'd2;
                                end
                            end
                            default: channel[ch] <= 1'b0;
                        endcase
                    end
                end
            endcase
        end
    end

    reg [7:0] testphase_r;
    assign testphase = testphase_r;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            testphase_r <= 8'h00;
        end else begin
            testphase_r[2:0] <= state;                      // 0..5
            testphase_r[3]   <= armed_mode;                 // latched after start
            testphase_r[4]   <= listening;                  // should follow state==ARMED
            testphase_r[5]   <= running;                    // should be 1 in RUN
            testphase_r[6]   <= trig_rise;                  // pulse when trigger edge seen
            testphase_r[7]   <= (ch0_delay_any | ch0_width_any); // "CH0 has work"
        end
    end

endmodule