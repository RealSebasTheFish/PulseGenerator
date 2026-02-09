`timescale 1ns/1ps
module async_fifo_8 #(
    parameter integer ADDR_BITS = 4  // depth = 2^ADDR_BITS (default 16 bytes)
)(
    // write domain
    input  wire       wclk,
    input  wire       wrst_n,
    input  wire       w_en,
    input  wire [7:0] w_data,
    output wire       w_full,

    // read domain
    input  wire       rclk,
    input  wire       rrst_n,
    input  wire       r_en,
    output reg  [7:0] r_data,
    output wire       r_empty
);
    localparam integer DEPTH = (1 << ADDR_BITS);

    reg [7:0] mem [0:DEPTH-1];

    // binary + gray pointers (ADDR_BITS+1 for full/empty distinction)
    reg [ADDR_BITS:0] wbin = 0, wgray = 0;
    reg [ADDR_BITS:0] rbin = 0, rgray = 0;

    // synced gray pointers
    reg [ADDR_BITS:0] wq1_rgray = 0, wq2_rgray = 0;
    reg [ADDR_BITS:0] rq1_wgray = 0, rq2_wgray = 0;

    function [ADDR_BITS:0] bin2gray(input [ADDR_BITS:0] b);
        bin2gray = (b >> 1) ^ b;
    endfunction

    // ===================== WRITE DOMAIN =====================

    // FIX: compute "full" from current registered wbin, not wgray_next
    // to avoid combinational loop: w_full -> wbin_next -> wgray_next -> w_full
    wire [ADDR_BITS:0] wgray_inc = bin2gray(wbin + 1'b1);

    assign w_full =
        (wgray_inc == {~rq2_wgray[ADDR_BITS:ADDR_BITS-1], rq2_wgray[ADDR_BITS-2:0]});

    wire [ADDR_BITS:0] wbin_next  = wbin + (w_en && !w_full);
    wire [ADDR_BITS:0] wgray_next = bin2gray(wbin_next);

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin  <= 0;
            wgray <= 0;
        end else begin
            if (w_en && !w_full) begin
                mem[wbin[ADDR_BITS-1:0]] <= w_data;
                wbin  <= wbin_next;
                wgray <= wgray_next;
            end
        end
    end

    // sync read pointer into write clock
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            rq1_wgray <= 0;
            rq2_wgray <= 0;
        end else begin
            rq1_wgray <= rgray;
            rq2_wgray <= rq1_wgray;
        end
    end

    // ===================== READ DOMAIN =====================
    wire [ADDR_BITS:0] rbin_next  = rbin + (r_en && !r_empty);
    wire [ADDR_BITS:0] rgray_next = bin2gray(rbin_next);

    assign r_empty = (rgray == wq2_rgray);

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin   <= 0;
            rgray  <= 0;
            r_data <= 8'h00;
        end else begin
            if (r_en && !r_empty) begin
                r_data <= mem[rbin[ADDR_BITS-1:0]];
                rbin   <= rbin_next;
                rgray  <= rgray_next;
            end
        end
    end

    // sync write pointer into read clock
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            wq1_rgray <= 0;
            wq2_rgray <= 0;
        end else begin
            wq1_rgray <= wgray;
            wq2_rgray <= wq1_rgray;
        end
    end
endmodule
