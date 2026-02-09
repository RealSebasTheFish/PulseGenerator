`timescale 1ns/1ps
module uart #(
    parameter CLK_HZ = 100_000_000,
    parameter BAUD   = 115_200
)(
    input  wire clk,
    input  wire rst,

    input  wire rx_i,
    output wire tx_o,

    output reg        rx_valid,
    output reg [7:0]  rx_data,

    input  wire       tx_valid,
    input  wire [7:0] tx_data,
    output reg        tx_ready,

    // ================= DEBUG =================
    output reg dbg_tx_tick,
    output reg dbg_rx_sample
);

    localparam integer DIV = CLK_HZ / BAUD;
    localparam integer OVERSAMPLE = 16;
    localparam integer RX_DIV =
        (CLK_HZ + (BAUD*OVERSAMPLE)/2) / (BAUD*OVERSAMPLE);

    // ================= RX =================
    reg [15:0] rx_cnt = 0;
    reg [5:0]  os_index = 0;
    reg [3:0]  rx_bit = 0;
    reg [7:0]  rx_shift = 0;
    reg        rx_busy = 0;
    reg        rx_sync1 = 1'b1, rx_sync2 = 1'b1;
    reg [1:0]  start_det = 2'b11;

    always @(posedge clk) begin
        rx_sync1 <= rx_i;
        rx_sync2 <= rx_sync1;
    end

    always @(posedge clk) begin
        rx_valid <= 1'b0;
        dbg_rx_sample <= 1'b0;

        if (rst) begin
            rx_cnt  <= 0;
            rx_busy <= 0;
            rx_bit  <= 0;
        end else begin
            start_det <= {start_det[0], rx_sync2};

            if (!rx_busy && start_det == 2'b10) begin
                rx_busy  <= 1'b1;
                rx_cnt   <= RX_DIV;
                os_index <= OVERSAMPLE + (OVERSAMPLE>>1);
                rx_bit   <= 0;
            end
            else if (rx_busy) begin
                if (rx_cnt == 0) begin
                    rx_cnt <= RX_DIV;
                    if (os_index != 0)
                        os_index <= os_index - 1;
                    else begin
                        os_index <= OVERSAMPLE - 1;
                        if (rx_bit < 8) begin
                            rx_shift <= {rx_sync2, rx_shift[7:1]};
                            rx_bit <= rx_bit + 1;
                            dbg_rx_sample <= 1'b1;
                        end else begin
                            rx_busy <= 0;
                            rx_data <= rx_shift;
                            rx_valid <= 1'b1;
                        end
                    end
                end else
                    rx_cnt <= rx_cnt - 1;
            end
        end
    end

    // ================= TX =================
    // Fully defined at all times
    reg [15:0] tx_cnt   = 16'd0;
    reg [3:0]  tx_bit   = 4'd0;
    reg [9:0]  tx_shift = 10'b1111111111; // idle high
    reg        tx_busy  = 1'b0;

    // UART idle must be HIGH
    assign tx_o = tx_shift[0];

    always @(posedge clk) begin
        dbg_tx_tick <= 1'b0;

        if (rst) begin
            tx_busy  <= 1'b0;
            tx_ready <= 1'b1;
            tx_shift <= 10'b1111111111;
            tx_cnt   <= 0;
            tx_bit   <= 0;
        end else begin
            if (!tx_busy) begin
                tx_ready <= 1'b1;

                if (tx_valid) begin
                    // Load frame: stop | data | start
                    tx_shift <= {1'b1, tx_data, 1'b0};
                    tx_busy  <= 1'b1;
                    tx_bit   <= 0;
                    tx_cnt   <= DIV - 1;
                    tx_ready <= 1'b0;
                end else begin
                    // 🔒 Enforce idle deterministically
                    tx_shift <= 10'b1111111111;
                end

            end else begin
                if (tx_cnt == 0) begin
                    tx_cnt   <= DIV - 1;
                    tx_shift <= {1'b1, tx_shift[9:1]}; // shift in known '1'
                    tx_bit   <= tx_bit + 1;
                    dbg_tx_tick <= 1'b1;

                    if (tx_bit == 9) begin
                        tx_busy  <= 1'b0;
                        tx_ready <= 1'b1;
                    end
                end else begin
                    tx_cnt <= tx_cnt - 1;
                end
            end
        end
    end

endmodule
