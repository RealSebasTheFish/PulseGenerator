`timescale 1ns/1ps
module usb_cmd_gateway (
    input  wire        clk,
    input  wire        rst,

    // RX bytes from UART
    input  wire        rx_valid,
    input  wire [7:0]  rx_data,

    // TX handshake (kept for compatibility; not used for throttling anymore)
    input  wire        tx_ready,
    output reg         resp_valid,
    output reg [7:0]   resp_data,

    // Decoded instruction
    output reg         cmd_valid,
    output reg [15:0]  cmd_instr,

    output wire        usbled
);
    assign usbled = rx_valid;

    // Frame format:
    // 55 AA LEN=4 CMD CH BLK DATA CRC_L CRC_H

    localparam S_SYNC0 = 3'd0,
               S_SYNC1 = 3'd1,
               S_LEN   = 3'd2,
               S_BODY  = 3'd3,
               S_CRC0  = 3'd4,
               S_CRC1  = 3'd5;

    localparam integer ACK_DELAY_CYCLES = 868;  // <<< added

    reg [2:0]  state = S_SYNC0;
    reg [7:0]  index;
    reg [15:0] crc, rx_crc;
    reg [7:0]  body [0:3];

    // ACK delay machinery
    reg        ack_pending = 1'b0;
    reg [7:0]  ack_data;
    reg [9:0]  ack_delay_cnt;

    // CRC16-CCITT (poly=0x1021, init=0xFFFF)
    function [15:0] crc16_ccitt;
        input [15:0] crc_in;
        input [7:0]  data;
        integer i;
        reg [15:0] c;
        begin
            c = crc_in ^ (data << 8);
            for (i=0; i<8; i=i+1)
                c = c[15] ? (c << 1) ^ 16'h1021 : (c << 1);
            crc16_ccitt = c;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_SYNC0;
            index         <= 0;
            crc           <= 16'hFFFF;
            rx_crc        <= 16'h0000;
            cmd_valid     <= 0;
            resp_valid    <= 0;
            resp_data     <= 8'h00;
            cmd_instr     <= 16'h0000;
            ack_pending   <= 0;
            ack_delay_cnt <= 0;
        end else begin
            cmd_valid  <= 0;
            resp_valid <= 0;

            // -----------------------------
            // ACK delay handler
            // -----------------------------
            if (ack_pending) begin
                if (ack_delay_cnt != 0)
                    ack_delay_cnt <= ack_delay_cnt - 1;
                else begin
                    resp_valid  <= 1'b1;
                    resp_data   <= ack_data;
                    ack_pending <= 1'b0;
                end
            end

            if (rx_valid  && !ack_pending) begin
                case (state)
                    S_SYNC0: begin
                        if (rx_data == 8'h55) state <= S_SYNC1;
                        else state <= S_SYNC0;
                    end

                    S_SYNC1: begin
                        if (rx_data == 8'hAA) state <= S_LEN;
                        else state <= S_SYNC0;
                    end

                    S_LEN: begin
                        if (rx_data == 8'd4) begin
                            index <= 0;
                            crc   <= 16'hFFFF;
                            state <= S_BODY;
                        end else begin
                            state <= S_SYNC0;
                        end
                    end

                    S_BODY: begin
                        body[index] <= rx_data;
                        crc         <= crc16_ccitt(crc, rx_data);
                        index       <= index + 1;
                        if (index == 3) state <= S_CRC0;
                    end

                    S_CRC0: begin
                        rx_crc[7:0] <= rx_data;
                        state <= S_CRC1;
                    end

                    S_CRC1: begin
                        rx_crc[15:8] <= rx_data;

                        if (crc == {rx_data, rx_crc[7:0]}) begin
                            cmd_instr <= {
                                body[0][2:0],  // opcode
                                body[1][1:0],  // channel
                                body[2][2:0],  // block
                                body[3]        // data
                            };
                            cmd_valid     <= 1'b1;
                            ack_data      <= 8'h06; // ACK
                        end else begin
                            ack_data      <= 8'h15; // NACK
                        end

                        ack_pending   <= 1'b1;
                        ack_delay_cnt <= ACK_DELAY_CYCLES;
                        state <= S_SYNC0;
                    end
                endcase
            end
        end
    end
endmodule
