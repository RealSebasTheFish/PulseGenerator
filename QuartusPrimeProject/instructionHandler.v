`timescale 1ns/1ps
module instructionHandler (
  input  [2:0]  opcode,
  input  [12:0] data,       // {ch[12:11], blk[10:8], byte[7:0]}
  output reg [12:0] delay,
  output reg [12:0] width,
  output reg [1:0]  control,
  output reg [3:0]  rw_signal // [r_delay, r_width, w_width, w_delay] (per your comment)
);

  localparam [2:0]
    OP_WR_DELAY = 3'b001,
    OP_WR_WIDTH = 3'b010,
    OP_START    = 3'b111,
    OP_STOP     = 3'b011,
    OP_RD_DELAY = 3'b101,
    OP_RD_WIDTH = 3'b110;

  always @* begin
    // defaults every cycle (NO latches)
    delay     = 13'd0;
    width     = 13'd0;
    control   = 2'b00;
    rw_signal = 4'b0000;

    case (opcode)
      OP_WR_DELAY: begin
        delay     = data;
        rw_signal = 4'b0001;
      end

      OP_WR_WIDTH: begin
        width     = data;
        rw_signal = 4'b0010;
      end

      OP_START: begin
        control   = 2'b11;
      end

      OP_STOP: begin
        control   = 2'b01;
      end

      OP_RD_DELAY: begin
        delay     = data;
        rw_signal = 4'b0100;
      end

      OP_RD_WIDTH: begin
        width     = data;
        rw_signal = 4'b1000;
      end

      default: begin
        // keep defaults
      end
    endcase
  end
endmodule