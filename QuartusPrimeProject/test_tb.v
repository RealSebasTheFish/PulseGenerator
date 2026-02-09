`timescale 1ns/1ps
module test_tb;


wire o1, o2;
reg a, b, c;


test_top_module dut(a, b, c, o1, o2);


initial begin
	a = 0;
	b = 0;
	c = 0;
	
	#100;
	
	a = 1;
	b = 0;
	c = 0;
	
	#100;
	
	a = 1;
	b = 1;
	c = 0;
	
	#100;
	
	a = 1;
	b = 1;
	c = 1;
	
	#100;
	
	$display("FINISH");
	
end




endmodule