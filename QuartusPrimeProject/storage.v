`timescale 1ns / 1ps

module storage #(parameter SIZE=8) (
    input clk,
    input reset,
    input write,
    input [SIZE-1:0] data_in,
    output reg [SIZE-1:0] stored_bit
);
initial begin
    stored_bit = {SIZE{1'b0}};
end

always @(posedge clk or posedge reset) begin
    if (reset) begin
        stored_bit <= {SIZE{1'b0}}; // Reset to 0
    end else if (write) begin
        stored_bit <= data_in; // Store the input data
    end
end

endmodule
