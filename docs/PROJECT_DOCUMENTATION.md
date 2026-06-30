# UART 16550 Project Documentation

## 1. Project Overview

This project implements a 16550-style UART in SystemVerilog. A UART, or Universal Asynchronous Receiver/Transmitter, converts parallel data from a host interface into serial frames and converts incoming serial frames back into parallel bytes.

The design is organized around five major blocks:

- A register/control block, `regs_uart`.
- A transmit serializer, `uart_tx_top`.
- A receive deserializer, `uart_rx_top`.
- A reusable FIFO, `fifo_top`.
- A top-level integration module, `all_mod`.

The project also includes `tb.sv`, a detailed testbench that configures the UART, loads FIFO data, observes transmission, drives receive frames, and prints the final internal states.

## 2. UART Frame Model

A UART frame is transmitted without a shared clock between endpoints. Both sides agree on baud rate and frame format in advance.

A normal frame has this order:

```text
idle high -> start bit low -> data bits LSB first -> optional parity -> stop bit(s) high -> idle high
```

This design supports:

| Field | Supported Values |
| --- | --- |
| Data length | 5, 6, 7, or 8 bits |
| Parity enable | Disabled or enabled |
| Parity type | Odd, even, mark/sticky-1, space/sticky-0 |
| Stop mode | 1 stop bit, 1.5 stop bits for 5-bit words, or 2 stop bits for wider words |
| Break | TX forced low when `set_break` is asserted |

The active data width is selected by `LCR[1:0]`, named `wls` in the code.

| `wls` | Data Bits |
| ---: | ---: |
| `00` | 5 |
| `01` | 6 |
| `10` | 7 |
| `11` | 8 |

## 3. Source File Summary

### `design.sv`

Contains all RTL modules and packed register structures:

- `fcr_t`: FIFO Control Register fields.
- `lcr_t`: Line Control Register fields.
- `lsr_t`: Line Status Register fields.
- `csr_t`: grouped CSR state.
- `div_t`: divisor latch MSB/LSB.
- `uart_tx_top`: TX state machine.
- `uart_rx_top`: RX state machine.
- `regs_uart`: register map and baud generator.
- `fifo_top`: common FIFO.
- `all_mod`: top-level wiring.

### `tb.sv`

Contains `all_mod_tb`, the verification environment. It generates a 100 MHz clock, resets the DUT, writes registers, sends FIFO data, recreates UART frames on `rx`, and prints the observed state.

The helper task `send_uart_byte` is important because it mirrors the configured UART format. It reads the DUT LCR fields, determines the active word length, computes parity, drives start/data/parity/stop bits on `rx`, and waits 16 baud pulses per UART bit.

## 4. Top-Level Architecture

`all_mod` is the top-level module. It connects the host register bus, serial pins, FIFOs, and UART engines.

```text
                 +----------------+
 wr/rd/addr/din  |                |  baud_pulse
 --------------> |   regs_uart    |--------------------+
                 |                |                    |
                 +-------+--------+                    |
                         | CSR fields                  |
                         v                             v
                 +---------------+              +---------------+
 din ----------> |    TX FIFO    | -- byte -->  |   uart_tx     | --> tx
                 +---------------+              +---------------+

 rx  ----------> +---------------+ -- byte -->  +---------------+
                 |   uart_rx     |              |    RX FIFO    | --> dout through regs
                 +---------------+              +---------------+
```

The register block is the center of the design. It:

- Decodes host reads and writes.
- Stores FCR, LCR, LSR, SCR, and divisor latch state.
- Generates `baud_pulse`.
- Pushes writes into the TX FIFO.
- Pops reads from the RX FIFO.
- Sends line-format settings to TX and RX.
- Updates status bits from FIFO and receiver signals.

## 5. Register Block

### 5.1 Divisor Latch Access

The Divisor Latch Access Bit is `LCR[7]`, named `dlab`.

When `dlab = 1`:

- Address `0` writes/reads divisor latch LSB.
- Address `1` writes/reads divisor latch MSB.

When `dlab = 0`:

- Address `0` writes TX data to THR/TX FIFO.
- Address `0` reads RX data from RHR/RX FIFO.

This matches the classic UART register overlay technique, where the same addresses have different meanings depending on DLAB.

### 5.2 Line Control Register

`lcr_t` is declared as:

```systemverilog
typedef struct packed {
  logic       dlab;
  logic       set_break;
  logic       stick_parity;
  logic       eps;
  logic       pen;
  logic       stb;
  logic [1:0] wls;
} lcr_t;
```

Because the struct is packed in this order, assigning an 8-bit value to `csr.lcr` maps:

| Bit | Field | Meaning |
| ---: | --- | --- |
| 7 | `dlab` | Divisor latch access. |
| 6 | `set_break` | Force `tx` low. |
| 5 | `stick_parity` | Enable mark/space parity interpretation with `eps`. |
| 4 | `eps` | Even parity select or sticky parity value selector. |
| 3 | `pen` | Parity enable. |
| 2 | `stb` | Stop-bit select. |
| 1:0 | `wls` | Word length select. |

Parity selection is encoded by `{stick_parity, eps}`:

| Encoding | Mode | Transmitted Parity Bit |
| ---: | --- | --- |
| `00` | Odd parity | Inverse of XOR reduction over active data bits |
| `01` | Even parity | XOR reduction over active data bits |
| `10` | Mark parity | Constant `1` |
| `11` | Space parity | Constant `0` |

### 5.3 FIFO Control Register

`fcr_t` stores:

| Bit(s) | Field | Meaning |
| ---: | --- | --- |
| 7:6 | `rx_trigger` | RX FIFO trigger threshold selector. |
| 5:4 | `reserved` | Reserved. |
| 3 | `dma_mode` | DMA mode bit. Stored but not otherwise used. |
| 2 | `tx_rst` | One-cycle TX FIFO reset pulse. |
| 1 | `rx_rst` | One-cycle RX FIFO reset pulse. |
| 0 | `ena` | FIFO enable bit. |

The RX threshold decoder produces:

| `rx_trigger` | Threshold |
| ---: | ---: |
| `00` | 1 byte |
| `01` | 4 bytes |
| `10` | 8 bytes |
| `11` | 14 bytes |

### 5.4 Line Status Register

`lsr_t` stores:

| Bit | Field | Meaning |
| ---: | --- | --- |
| 0 | `dr` | Data ready. RX FIFO is not empty. |
| 1 | `oe` | Overrun error. |
| 2 | `pe` | Parity error. |
| 3 | `fe` | Framing error. |
| 4 | `bi` | Break indicator. |
| 5 | `thre` | TX holding register/FIFO empty. |
| 6 | `temt` | TX serializer empty. |
| 7 | `rx_fifo_error` | Reserved for RX FIFO aggregate error behavior. |

On reset, LSR is initialized to `8'h60`, meaning `THRE=1` and `TEMT=1`.

## 6. Baud Generator

The baud generator is implemented in `regs_uart` using a 16-bit down-counter. The divisor latch is stored as:

```systemverilog
div_t dl;
```

The counter reloads from `dl` when:

- Reset occurs.
- The divisor latch is updated.
- The counter reaches zero.

`baud_pulse` is asserted when the divisor is nonzero and the counter reaches zero:

```systemverilog
baud_pulse <= |dl & ~|baud_cnt;
```

The testbench calculates the expected baud using:

```text
baud = 100000000 / (div_latch * 16)
```

The factor of 16 reflects the UART 16x oversampling-style timing used by the TX and RX logic.

## 7. Transmitter

`uart_tx_top` converts FIFO bytes into serial bits on `tx`.

### 7.1 Inputs

| Signal | Meaning |
| --- | --- |
| `baud_pulse` | Advances the TX state machine. |
| `pen` | Enables parity bit transmission. |
| `thre` | Indicates the TX FIFO is empty. |
| `stb` | Selects stop-bit timing. |
| `sticky_parity`, `eps` | Select parity mode. |
| `set_break` | Forces `tx` low. |
| `din` | Byte from TX FIFO. |
| `wls` | Active word length. |

### 7.2 Outputs

| Signal | Meaning |
| --- | --- |
| `pop` | Requests the next byte from TX FIFO. |
| `sreg_empty` | Indicates the TX shift register is empty. |
| `tx` | Serial transmit line. |

### 7.3 TX State Machine

The transmitter uses four states:

| State | Behavior |
| --- | --- |
| `idle` | Waits for TX FIFO data. When data exists, asserts `pop`, loads `shft_reg`, drives start bit low. |
| `start` | Holds the start bit for one bit time. Computes active-data parity. |
| `send` | Shifts data LSB first. After the last data bit, either sends parity or enters stop timing. |
| `parity` | Sends the parity bit, then returns to idle after stop timing is set. |

The output is:

```systemverilog
tx = tx_data & ~set_break;
```

This means normal TX data is sent when break is disabled, and the TX line is forced low when break is enabled.

## 8. Receiver

`uart_rx_top` samples incoming serial frames from `rx`.

### 8.1 RX State Machine

The receiver uses five states:

| State | Behavior |
| --- | --- |
| `idle` | Watches for the beginning of a frame. |
| `start` | Waits to the middle of the start bit and verifies it is still low. |
| `read` | Samples each data bit near the middle of the bit period and shifts it into `dout`. |
| `parity` | Samples/checks the parity result when parity is enabled. |
| `stop` | Samples the stop bit and asserts `push` into the RX FIFO. |

The receive path stores active-width data into an 8-bit `dout`, zero-extending unused upper bits for 5-, 6-, and 7-bit modes.

### 8.2 Error Detection

The receiver produces:

| Signal | Meaning |
| --- | --- |
| `pe` | Parity error. |
| `fe` | Framing error when the stop sample is low. |
| `bi` | Break indicator output, present in the interface. |

The testbench result screenshots show `pe=0`, `fe=0`, `bi=0`, and final `Error count:0` in all stored runs.

## 9. FIFO

`fifo_top` is used for both TX and RX.

### 9.1 Interface

| Signal | Direction | Meaning |
| --- | --- | --- |
| `push_in` | input | Request to write `din`. |
| `pop_in` | input | Request to read current `dout`. |
| `din` | input | Write data. |
| `dout` | output | Current read-pointer data. |
| `empty` | output | FIFO count is zero. |
| `full` | output | FIFO count has reached the full condition. |
| `overrun` | output | Push attempted while full. |
| `underrun` | output | Pop attempted while empty. |
| `threshold` | input | Trigger level. |
| `thre_trigger` | output | Count is greater than or equal to threshold. |

### 9.2 Push and Pop Behavior

Pushes are accepted when `push_in` is high and the FIFO is not full:

```systemverilog
assign push = push_in && !full;
```

Pops are edge-detected:

```systemverilog
assign pop_edge = pop_in && !pop_in_r;
assign pop = pop_edge && !empty;
```

This prevents a multi-cycle `pop_in` pulse from removing multiple entries.

## 10. Testbench Methodology

The testbench is designed for visibility. It prints each major phase:

- Reset completion.
- Initial LCR state.
- Divisor latch configuration.
- Final LCR data format.
- TX FIFO configuration.
- TX FIFO writes.
- TX serializer activity.
- RX frame reception.
- RX FIFO final state.
- Final error count.

The testbench uses hierarchical references such as `dut.csr.lcr.wls`, `dut.tx_fifo_inst.mem[i]`, and `dut.uart_tx_inst.pop`. This makes the output very educational because the console shows internal UART behavior, not only top-level pins.

The receive helper task:

```systemverilog
task automatic send_uart_byte(input [7:0] data);
```

does four important things:

1. Determines active word length from `dut.csr.lcr.wls`.
2. Drives a start bit.
3. Sends only the active data bits, LSB first.
4. Generates parity and stop timing according to the programmed LCR.

This makes the receiver test track the same configuration that the DUT is using.

## 11. Captured Results

### 11.1 9600 Baud, Odd Parity, 8 Data Bits, 1 Stop Bit

Configuration:

```text
div_latch = 651
baud rate = 9600 Hz
LCR: dlab=0 set_break=0 stick_parity=0 eps=0 pen=1 stb=0 wls=3
```

Payload:

```text
227, 11, 212, 246, 197, 193, 67, 168
```

Result:

```text
All 8 bytes transmitted successfully.
All 8 bytes received successfully.
RX FIFO final count = 8.
Error count = 0.
```

### 11.2 19200 Baud, Even Parity, 7 Data Bits, 2 Stop Bits

Configuration:

```text
div_latch = 326
baud rate = 19171 Hz
LCR: dlab=0 set_break=0 stick_parity=0 eps=1 pen=1 stb=1 wls=2
```

Payload:

```text
105, 33, 15, 97, 24, 84, 17, 0
```

Result:

```text
All 8 bytes received successfully.
RX FIFO final count = 8.
Error count = 0.
```

### 11.3 38400 Baud, Space Parity, 5 Data Bits, 1.5 Stop Bits

Configuration:

```text
div_latch = 163
baud rate = 38343 Hz
LCR: dlab=0 set_break=0 stick_parity=1 eps=1 pen=1 stb=1 wls=0
```

Payload:

```text
3, 11, 20, 22, 5, 1, 3, 8
```

Result:

```text
All 8 bytes received successfully.
RX FIFO final count = 8.
Error count = 0.
```

### 11.4 9600 Baud, Mark Parity, 6 Data Bits, 1 Stop Bit

Configuration:

```text
div_latch = 651
baud rate = 9600 Hz
LCR: dlab=0 set_break=0 stick_parity=1 eps=0 pen=1 stb=0 wls=1
```

Payload:

```text
35, 11, 20, 54, 5, 1, 3, 40
```

Result:

```text
All 8 bytes received successfully.
RX FIFO final count = 8.
Error count = 0.
```

## 12. Waveform Interpretation

The waveform screenshots in `Waveform/Baud9600_OddParity_8bit_1StopBit` demonstrate the complete movement of data through the UART.

### Baud Generation

`Baud_generation.png` shows:

- `div_latch[15:0] = 651`.
- Calculated baud value of `9600`.
- Baud pulse activity used by both TX and RX logic.

### UART Transmitter

`UART_Transmitter.png` shows:

- `din[7:0]` stepping through the FIFO payload.
- `tx` toggling through serial frames.
- TX state moving through `send` and finally returning to `idle`.
- `pop` pulses requesting bytes from the TX FIFO.
- `sreg_empty` asserting after transmission completes.
- `wls=3`, `pen=1`, `sticky_parity=0`, `eps=0`, `stb=0`, matching 8-bit odd parity with 1 stop bit.

### UART Receiver

`UART_Receiver.png` shows:

- `rx` serial activity.
- RX state entering `read`.
- `dout[7:0]` reconstructing the payload values.
- `push` pulses into RX FIFO.
- `fe=0` and `bi=0`, consistent with the zero-error console result.

### FIFOs and CSR

The FIFO waveforms show count movement, memory output, push/pop activity, and empty/full status. The CSR waveform connects register programming to the resulting baud and line-format behavior.

## 13. Design Strengths

- Clear modular structure: TX, RX, FIFO, and register logic are separated cleanly.
- LCR and FCR are represented as packed structs, which makes bitfields readable.
- The testbench prints human-readable explanations of register configuration and UART behavior.
- Multiple frame formats were tested, including odd/even parity and sticky parity.
- The receiver task adapts dynamically to the DUT LCR settings, reducing duplicated testbench configuration mistakes.
- Stored schematic, waveform, and console screenshots make the repository understandable even before running a simulator.

## 14. Implementation Notes and Future Improvements

These notes are useful if the project is extended toward a more complete 16550-compatible UART.

### 14.1 Interrupt Registers

IER and IIR are placeholders. A full 16550 implementation would add:

- RX data available interrupt.
- THR empty interrupt.
- Receiver line status interrupt.
- Character timeout interrupt.
- Interrupt priority encoding through IIR.

### 14.2 Modem Registers

MCR and MSR currently read as zero. A complete UART may support:

- RTS, CTS.
- DTR, DSR.
- DCD, RI.
- Loopback mode.

### 14.3 RX Overrun Status

In the current top-level wiring, the LSR overrun input is driven from the TX FIFO overrun signal. For 16550-style status, `LSR[1]` should report receive overrun, so the RX FIFO overrun signal should feed the register block.

### 14.4 Assertion-Based Verification

The current testbench demonstrates behavior very clearly through logs. For regression testing, add assertions such as:

- TX FIFO count increases on valid THR writes.
- TX pop count equals transmitted byte count.
- RX FIFO contents match expected bytes.
- No parity/framing error occurs for valid frames.
- Parity error asserts for intentionally corrupted parity frames.
- Framing error asserts when the stop bit is forced low.
- Overrun asserts when pushing into a full RX FIFO.


