`timescale 1ns / 1ps

module muxBase(out, a0, a1, sel);
    output out;
    input a0, a1, sel;
    wire notC, upper, lower;
    not my_not(notC, sel);
    and upperAnd(upper, a0, notC);
    and lowerAnd(lower, sel, a1);
    or my_or(out, upper, lower);
endmodule

module mux(out, a0, a1, sel);
    parameter WIDTH = 2;
    output [WIDTH-1:0] out;
    input [WIDTH-1:0] a0, a1;
    input sel;
    muxBase mine[WIDTH-1:0](out, a0, a1, sel);
endmodule

module mux4(out, a0,a1,a2,a3, sel);
    parameter WIDTH = 2;
    output [WIDTH-1:0] out;
    input [WIDTH-1:0] a0, a1, a2, a3;
    input [1:0] sel;
    wire [WIDTH-1:0] zLo, zHi;
    mux #(WIDTH) lo(zLo, a0, a1, sel[0]);
    mux #(WIDTH) hi(zHi, a2, a3, sel[0]);
    mux #(WIDTH) final(out, zLo, zHi, sel[1]);
endmodule

module mux8(out, a0,a1,a2,a3, a4, a5, a6, a7, sel);
    parameter WIDTH = 2;
    output [WIDTH-1:0] out;
    input [WIDTH-1:0] a0, a1, a2, a3, a4, a5, a6, a7;
    input [2:0] sel;
    wire [WIDTH-1:0] zLo, zHi;
    mux4 #(WIDTH) lo(zLo, a0, a1, a2, a3, sel[1:0]);
    mux4 #(WIDTH) hi(zHi, a4, a5, a6, a7, sel[1:0]);
    mux #(WIDTH) final(out, zLo, zHi, sel[2]);
endmodule
