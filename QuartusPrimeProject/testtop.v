module testtop (
    input  wire        clk50,
    output wire [3:0]   channel,
    output wire [9:0]   ledr
);
    reg [25:0] div = 0;
    always @(posedge clk50) div <= div + 1'b1;

    // Constant high on channel pins
    assign channel = 4'b1111;

    // Blink LEDR[0] so you know FPGA is running
    assign ledr[0] = div[25];
    assign ledr[9:1] = 9'b0;
endmodule