# PulseGenerator

4-channel digital pulse generator implemented on the Intel MAX 10 DE10-Lite FPGA.
Designed for physics lab use where deterministic trigger-relative timing is needed
and software-based solutions introduce too much jitter.

## How it works

The system operates in two phases:

**Configuration** — The user sets delay and width values for each of the 4 output
channels using the Windows software client. Settings are sent to the FPGA over USB
via UART at 115200 baud and stored in internal hardware registers.

**Execution** — After issuing a start command, the FPGA listens for a rising edge
on the trigger input. On detection, all 4 channels begin counting down their
programmed delays concurrently in hardware. Each channel asserts its output high
for the programmed width once its delay expires. No software is involved after
the start command is issued.

The timing core runs at 200 MHz, giving a 5ns resolution on all delays and widths.
Total trigger-to-output latency is fixed at ~40ns and can be compensated in software.

## Repo structure
```
QuartusPrimeProject/    Verilog source + Quartus project files
PulseGeneratorSoftware/ Windows GUI client (PulseGenerator.exe)
```

## Setup

See the full user guide for step-by-step setup instructions covering Quartus
pin assignments, compilation, flashing, and software installation.
`Pulse_Generator_User_Manual.pdf`

## Requirements

- Intel MAX 10 DE10-Lite FPGA
- Quartus Prime Lite 22.1
- Windows (for the software client)
- CP210x USB to UART driver