`timescale 1ns / 1ps

module deMuxBase (
  input  wire in,
  input  wire sel,     // 0 -> out0, 1 -> out1
  output wire a0, a1
);
  wire nsel;
  not (nsel, sel);
  and (a0, in, nsel);
  and (a1, in, sel);
endmodule

module deMux #(parameter WIDTH=8) (
  input  wire [WIDTH-1:0] in,
  input  wire sel,                     // 0 -> out0, 1 -> out1
  output wire [WIDTH-1:0] a0, a1
);
  deMuxBase u[WIDTH-1:0](in, sel, a0, a1);
endmodule

module deMux4(in, a0, a1, a2, a3, sel); 
    parameter WIDTH = 8; 
    input [WIDTH-1:0] in; 
    output [WIDTH-1:0] a0, a1, a2, a3; 
    input [1:0] sel; 
    wire [WIDTH-1:0] zLo, zHi; 
    deMux #(WIDTH) first(.in(in), .a0(zLo), .a1(zHi), .sel(sel[1]));
    deMux #(WIDTH) l1(.in(zLo), .a0(a0), .a1(a1), .sel(sel[0])); 
    deMux #(WIDTH) l2(.in(zHi), .a0(a2), .a1(a3), .sel(sel[0])); 
endmodule

module deMux8(in, a0, a1, a2, a3, a4, a5, a6, a7, sel); 
    parameter WIDTH = 8; 
    input [WIDTH-1:0] in; 
    output [WIDTH-1:0] a0, a1, a2, a3, a4, a5, a6, a7; 
    input [2:0] sel; 
    wire [WIDTH-1:0] zLo, zHi; 
    deMux #(WIDTH) first(.in(in), .a0(zLo), .a1(zHi), .sel(sel[2]));
    deMux4 #(WIDTH) l1(.in(zLo), .a0(a0), .a1(a1), .a2(a2), .a3(a3), .sel(sel[1:0])); 
    deMux4 #(WIDTH) l2(.in(zHi), .a0(a4), .a1(a5), .a2(a6), .a3(a7), .sel(sel[1:0])); 
endmodule

