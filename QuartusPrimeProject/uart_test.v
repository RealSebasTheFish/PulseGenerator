module uart_test (
    input  wire rx, // GPIO[0] is RX, GPIO[1] is TX
	 output wire tx,
    output wire LEDR  // Visual feedback
);

    // Simple Loopback: Connect RX directly to TX
    assign tx = rx;

    // Light up the first LED when the line is IDLE (UART High)
    // This helps you see if the connection is alive.
    assign LEDR = rx;

endmodule