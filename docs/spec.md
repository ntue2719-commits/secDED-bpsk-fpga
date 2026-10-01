# Technical Specification — SECDED + BPSK FPGA Pipeline

**Status:** Python reference implemented; RTL implementation planned  
**Clock target:** 50 MHz · **UART:** 115200 baud, 8-N-1 · **Payload:** 4 bits  
**Coding:** Extended Hamming SECDED (8,4) · **Modulation:** BPSK, 8 samples/bit  
**Reference:** `python/golden_model.py`

This document defines the software algorithmic reference and intended RTL module interfaces. It does not claim that the hardware modules have already been implemented or validated.

## 1. Architecture

```text
UART RX -> UART Controller -> tx_rx_dsp_top
                                  |
             +--------------------+---------------------+
             |                    |                     |
      hamming_encoder     bit_flip_channel       bpsk_modulator
                                                       |
                                               lfsr_noise_injector
                                                       |
                                               bpsk_demodulator
                                                       |
                                                hamming_decoder
                                  |
UART TX <---------------- UART Controller
```

The DSP path processes one 4-bit payload at a time. `error_lfsr` and `noise_lfsr` are independent, deterministic state machines. They are initialized on reset and are not reseeded between normal transactions.

## 2. Global Interface and Timing Rules

| Item | Contract |
|---|---|
| Clock | 50 MHz, 20 ns |
| Reset | Active-low `i_rst_n` |
| UART | 115200 baud, 8-N-1 |
| `CLKS_PER_BIT` | 434 |
| Payload/codeword | 4-bit payload, 8-bit codeword |
| BPSK mapping | `0 → +127`, `1 → -127` |
| Samples | 8 per bit, 64 per codeword |
| Sample format | Signed 8-bit two's complement |
| Bit order | MSB-first |
| Noise level | 0..7 |
| Error mode | 0..3 |
| Demod decision | Sum >= 0 means bit 0; sum < 0 means bit 1 |
| Saturation | Clamp to signed 8-bit range [-128,+127] |
| `valid` | Current-cycle data is valid |
| `done` | Current valid item is the final stream item; `done` implies `valid` |
| `start` | One-cycle request, accepted only when target block is idle |
| LFSRs | No reseed between transactions |

## 3. UART Protocol

### Host to FPGA

Two bytes per request.

```text
CONFIG = {3'b000, noise_level[2:0], err_mode[1:0]}
DATA   = {data_hi[3:0], data_lo[3:0]}
```

The controller runs `data_hi` and then `data_lo` as two DSP transactions.

### FPGA to Host

```text
Response Byte 0 = {result[3:0], 4'b0000}
Response Byte 1 = {6'b000000, status[1:0]}
```

| Status | Meaning |
|---|---|
| `00` | No error detected |
| `01` | Single-bit error corrected |
| `10` | Double-bit error detected |
| `11` | Not normally generated |

**Integration issue:** one response status field cannot independently report the status of both nibble transactions. Before finalizing the controller, define whether the response reports the high nibble, low nibble, an aggregate, or extend the protocol.

## 4. Software Algorithms — Golden Model

The Python model is the bit-level reference for RTL verification.

### 4.1 Hamming SECDED Encoder

Mapping:

```text
codeword = {p0,d3,d2,d1,p3,d0,p2,p1}
[7]=p0 [6]=d3 [5]=d2 [4]=d1 [3]=p3 [2]=d0 [1]=p2 [0]=p1
```

Parity:

```text
p1 = d0 ^ d1 ^ d3
p2 = d0 ^ d2 ^ d3
p3 = d1 ^ d2 ^ d3
p0 = p1 ^ p2 ^ d0 ^ p3 ^ d1 ^ d2 ^ d3
```

`p0` makes total codeword parity even.

### 4.2 Bit-Error Injection

Error LFSR reset seed is `8'hA5`.

```text
feedback = state[7] ^ state[5] ^ state[4] ^ state[3]
next     = {state[6:0], feedback}
```

If the next state is zero, recover to `8'hA5`. Use the current state to select positions, then update once per codeword.

| Mode | Operation |
|---|---|
| `00` | No bit flip |
| `01` | `pos = state[2:0]`; flip bit `pos` |
| `10` | `pos1 = state[2:0]`, `pos2 = state[5:3]`; flip both |
| `11` | Reserved; treated as no error |

If `pos1 == pos2`, set `pos2 = (pos2 + 1) mod 8`. The LFSR advances once for every codeword, including modes `00` and `11`.

### 4.3 BPSK Modulation

For bits from codeword bit 7 down to bit 0, emit eight samples per bit:

```text
bit 0 -> +127, repeated 8 times
bit 1 -> -127, repeated 8 times
```

The resulting stream contains 64 samples.

### 4.4 Noise Injection

Noise LFSR reset seed is `8'h01`, with the same feedback equation. If the next state is zero, recover to `8'h01`.

| Noise level | Amplitude |
|---:|---:|
| 0 | 0 |
| 1 | 4 |
| 2 | 8 |
| 3 | 16 |
| 4 | 24 |
| 5 | 32 |
| 6 | 48 |
| 7 | 64 |

For each valid sample:

```text
state[7] = 0 -> noise = +amplitude
state[7] = 1 -> noise = -amplitude
raw = signed(sample) + signed(noise)
output = clamp(raw, -128, +127)
```

Advance the noise LFSR once per valid sample, including level zero. Saturation is required; wrapping is not allowed.

### 4.5 BPSK Demodulation

Sum each group of eight signed samples with a signed 11-bit accumulator:

```text
correlation >= 0 -> detected bit 0
correlation <  0 -> detected bit 1
```

Reconstruct the codeword MSB-first. The accumulator's theoretical sum range is `-1024..+1016`.

### 4.6 Hamming SECDED Decoder

```text
S1 = p1 ^ d0 ^ d1 ^ d3
S2 = p2 ^ d0 ^ d2 ^ d3
S3 = p3 ^ d1 ^ d2 ^ d3
S  = {S3,S2,S1}
P  = XOR of all eight received bits
```

| Syndrome | Overall parity `P` | Action | Status |
|---|---:|---|---|
| `000` | 0 | No correction | `00` |
| Non-zero | 1 | Flip codeword bit `S-1` (bit 0..6) | `01` |
| `000` | 1 | Flip bit 7 (`p0`) | `01` |
| Non-zero | 0 | Detect double-bit error; do not correct | `10` |

Extract data as `{corrected_word[6], corrected_word[5], corrected_word[4], corrected_word[2]}`. For a double-bit error, return `data=0`, `status=2`; the zero data is diagnostic, not recovered payload.

### 4.7 Transaction Order

```text
1. Encode payload
2. Inject bit error using current error LFSR; update once
3. Generate 64 BPSK samples
4. Add noise; update noise LFSR once per sample
5. Demodulate 64 samples into a codeword
6. SECDED-decode received codeword
7. Return result, status, and intermediate debug values
```

`GoldenModel` preserves LFSR states between calls. Instantiate a new model only to represent reset.

## 5. Hardware Files and Complete Signal Lists

The following is the intended RTL file set and port contract.

### 5.1 `fpga_top.v` — Board-level wrapper

```verilog
module fpga_top (
    input wire i_clk, input wire i_rst_n,
    input wire i_uart_rx, output wire o_uart_tx
);
```

| Signal | Dir. | Width | Purpose |
|---|---|---:|---|
| `i_clk` | In | 1 | 50 MHz clock |
| `i_rst_n` | In | 1 | Active-low reset |
| `i_uart_rx` | In | 1 | UART receive pin |
| `o_uart_tx` | Out | 1 | UART transmit pin |

### 5.2 `uart_rx.v` — Serial receiver

```verilog
module uart_rx (
    input wire i_clk, input wire i_rst_n, input wire i_rx,
    output reg [7:0] o_data, output reg o_valid
);
```

| Signal | Dir. | Width | Purpose |
|---|---|---:|---|
| `i_clk` | In | 1 | System clock |
| `i_rst_n` | In | 1 | Active-low reset |
| `i_rx` | In | 1 | Serial input |
| `o_data` | Out | 8 | Received byte |
| `o_valid` | Out | 1 | One-cycle pulse after valid frame |

8-N-1 frame: start `0`, D0..D7 LSB-first, stop `1`. With 434 clocks/bit, sample the start bit near its center after 217 clocks, then sample each data bit every 434 clocks.

### 5.3 `uart_tx.v` — Serial transmitter

```verilog
module uart_tx (
    input wire i_clk, input wire i_rst_n,
    input wire [7:0] i_data, input wire i_start,
    output reg o_tx, output reg o_busy
);
```

| Signal | Dir. | Width | Purpose |
|---|---|---:|---|
| `i_clk` | In | 1 | System clock |
| `i_rst_n` | In | 1 | Active-low reset |
| `i_data` | In | 8 | Byte to send |
| `i_start` | In | 1 | One-cycle request, accepted while idle |
| `o_tx` | Out | 1 | Serial output, idle high |
| `o_busy` | Out | 1 | High while transmitting |

### 5.4 `uart_controller.v` — Protocol/FSM controller

```verilog
module uart_controller (
    input wire i_clk, input wire i_rst_n,
    input wire [7:0] i_rx_data, input wire i_rx_valid,
    input wire [3:0] i_dsp_result, input wire [1:0] i_dsp_status,
    input wire i_dsp_done, input wire i_tx_busy,
    output reg [3:0] o_dsp_data, output reg [2:0] o_noise_level,
    output reg [1:0] o_err_mode, output reg o_dsp_start,
    output reg [7:0] o_tx_data, output reg o_tx_start
);
```

| Signal | Dir. | Width | Purpose |
|---|---|---:|---|
| `i_clk` | In | 1 | System clock |
| `i_rst_n` | In | 1 | Active-low reset |
| `i_rx_data` | In | 8 | UART RX byte |
| `i_rx_valid` | In | 1 | RX byte-valid pulse |
| `i_dsp_result` | In | 4 | DSP result |
| `i_dsp_status` | In | 2 | Decoder status |
| `i_dsp_done` | In | 1 | Transaction completion |
| `i_tx_busy` | In | 1 | UART TX busy |
| `o_dsp_data` | Out | 4 | DSP payload nibble |
| `o_noise_level` | Out | 3 | Configured noise level |
| `o_err_mode` | Out | 2 | Configured error mode |
| `o_dsp_start` | Out | 1 | One-cycle DSP request |
| `o_tx_data` | Out | 8 | UART response byte |
| `o_tx_start` | Out | 1 | One-cycle TX request |

Behavior: receive CONFIG, receive DATA, process high nibble then low nibble, then send the response. Do not accept a new packet while processing the current one. Wait for TX idle/completion before starting the next response byte.

### 5.5 `tx_rx_dsp_top.v` — DSP transaction wrapper

```verilog
module tx_rx_dsp_top (
    input wire i_clk, input wire i_rst_n,
    input wire [3:0] i_data, input wire [2:0] i_noise_level,
    input wire [1:0] i_err_mode, input wire i_start,
    output reg [3:0] o_data, output reg [1:0] o_status,
    output reg o_done
);
```

| Signal | Dir. | Width | Purpose |
|---|---|---:|---|
| `i_clk` | In | 1 | System clock |
| `i_rst_n` | In | 1 | Active-low reset |
| `i_data` | In | 4 | Payload |
| `i_noise_level` | In | 3 | Noise level |
| `i_err_mode` | In | 2 | Error mode |
| `i_start` | In | 1 | One-cycle request when idle |
| `o_data` | Out | 4 | Decoded data |
| `o_status` | Out | 2 | Decoder status |
| `o_done` | Out | 1 | Transaction-level completion pulse |

`o_done` is transaction-level, not sample-level. It must be sampled consistently with `o_data` and `o_status`; define the exact output-valid cycle in RTL and testbench.

### 5.6 `hamming_encoder.v` — SECDED encoder

```verilog
module hamming_encoder (
    input wire i_clk, input wire i_rst_n,
    input wire [3:0] i_data, input wire i_start,
    output reg [7:0] o_codeword, output reg o_valid
);
```

| Signal | Dir. | Width | Purpose |
|---|---|---:|---|
| `i_clk` | In | 1 | System clock |
| `i_rst_n` | In | 1 | Active-low reset |
| `i_data` | In | 4 | Payload |
| `i_start` | In | 1 | One-cycle request |
| `o_codeword` | Out | 8 | Encoded codeword |
| `o_valid` | Out | 1 | One-cycle output-valid pulse |

Intended latency: request sampled at cycle N, output valid at cycle N+1.

### 5.7 `bit_flip_channel.v` — Error injection

```verilog
module bit_flip_channel (
    input wire i_clk, input wire i_rst_n,
    input wire [7:0] i_codeword, input wire i_valid,
    input wire [1:0] i_err_mode,
    output reg [7:0] o_codeword, output reg o_valid
);
```

| Signal | Dir. | Width | Purpose |
|---|---|---:|---|
| `i_clk` | In | 1 | System clock |
| `i_rst_n` | In | 1 | Active-low reset |
| `i_codeword` | In | 8 | Encoded word |
| `i_valid` | In | 1 | Input valid |
| `i_err_mode` | In | 2 | Error mode |
| `o_codeword` | Out | 8 | Possibly corrupted word |
| `o_valid` | Out | 1 | One-cycle delayed valid |

Intended latency: one clock. Error LFSR resets to `8'hA5`.

### 5.8 `bpsk_modulator.v` — BPSK sample generator

```verilog
module bpsk_modulator (
    input wire i_clk, input wire i_rst_n,
    input wire [7:0] i_codeword, input wire i_valid,
    output reg signed [7:0] o_sample,
    output reg o_valid, output reg o_done
);
```

| Signal | Dir. | Width | Purpose |
|---|---|---:|---|
| `i_clk` | In | 1 | System clock |
| `i_rst_n` | In | 1 | Active-low reset |
| `i_codeword` | In | 8 | Input codeword |
| `i_valid` | In | 1 | Input word valid |
| `o_sample` | Out | signed 8 | BPSK sample |
| `o_valid` | Out | 1 | High for each of 64 samples |
| `o_done` | Out | 1 | High with sample 63 only |

Emit bits MSB-first, eight repeated samples per bit. `o_done` implies `o_valid`.

### 5.9 `lfsr_noise_injector.v` — Sample noise

```verilog
module lfsr_noise_injector (
    input wire i_clk, input wire i_rst_n,
    input wire signed [7:0] i_sample,
    input wire i_valid, input wire i_done,
    input wire [2:0] i_noise_level,
    output reg signed [7:0] o_sample,
    output reg o_valid, output reg o_done
);
```

| Signal | Dir. | Width | Purpose |
|---|---|---:|---|
| `i_clk` | In | 1 | System clock |
| `i_rst_n` | In | 1 | Active-low reset |
| `i_sample` | In | signed 8 | Input sample |
| `i_valid` | In | 1 | Input sample valid |
| `i_done` | In | 1 | Marks final valid sample |
| `i_noise_level` | In | 3 | Noise selector |
| `o_sample` | Out | signed 8 | Saturated noisy sample |
| `o_valid` | Out | 1 | One-cycle delayed valid |
| `o_done` | Out | 1 | One-cycle delayed final marker |

Intended latency: exactly one clock for sample, valid, and done. Noise LFSR resets to `8'h01` and advances once per valid sample.

### 5.10 `bpsk_demodulator.v` — Correlation demodulator

```verilog
module bpsk_demodulator (
    input wire i_clk, input wire i_rst_n,
    input wire signed [7:0] i_sample,
    input wire i_valid, input wire i_done,
    output reg [7:0] o_codeword, output reg o_valid
);
```

| Signal | Dir. | Width | Purpose |
|---|---|---:|---|
| `i_clk` | In | 1 | System clock |
| `i_rst_n` | In | 1 | Active-low reset |
| `i_sample` | In, signed | 8 | Noisy sample |
| `i_valid` | In | 1 | Sample valid |
| `i_done` | In | 1 | Marks final sample |
| `o_codeword` | Out | 8 | Demodulated codeword |
| `o_valid` | Out | 1 | One-cycle codeword-valid pulse |

Accumulate eight samples per bit with a signed 11-bit accumulator. Decide bit 0 for non-negative sum and bit 1 for negative sum. Reconstruct MSB-first and output after processing the final sample.

### 5.11 `hamming_decoder.v` — SECDED decoder

```verilog
module hamming_decoder (
    input wire i_clk, input wire i_rst_n,
    input wire [7:0] i_codeword, input wire i_valid,
    output reg [3:0] o_data, output reg [1:0] o_status,
    output reg o_valid
);
```

| Signal | Dir. | Width | Purpose |
|---|---|---:|---|
| `i_clk` | In | 1 | System clock |
| `i_rst_n` | In | 1 | Active-low reset |
| `i_codeword` | In | 8 | Received word |
| `i_valid` | In | 1 | Input valid |
| `o_data` | Out | 4 | Corrected payload or diagnostic zero |
| `o_status` | Out | 2 | Decoder status |
| `o_valid` | Out | 1 | One-cycle output-valid pulse |

Intended latency: one clock from accepted codeword to decoded output.

## 6. Reset Contract

On active-low reset, FSMs return to IDLE; valid/done/busy pulses clear; counters and accumulators clear; error LFSR becomes `8'hA5`; noise LFSR becomes `8'h01`; UART TX returns to idle high; outputs/status clear to zero unless an explicit safe idle value is documented. Do not reseed LFSRs between normal transactions.

## 7. Verification Plan

| Block | Minimum coverage |
|---|---|
| Encoder | All 16 input values |
| Decoder, no error | All 16 payloads |
| Decoder, single bit | 16 payloads × 8 positions |
| Decoder, double bit | 16 payloads × 28 unique pairs |
| BPSK | All 256 codewords |
| Noise | Levels 0..7, sign, sequence, saturation |
| Full DSP | 16 × 8 × 3 = 384 cases |
| UART | CONFIG/DATA, response bytes, framing, order |
| Integration | Compare RTL and Python at intermediate stages |

Debug in this order: `encoded_word` → `corrupted_word/error_lfsr` → `bpsk_sample` → `noise_lfsr/noise_value/noisy_sample` → `received_codeword` → `syndrome/parity/corrected_word` → `decoded_data/status`.

## 8. Quick Start

From the repository root:

```bash
python -m pip install -r requirements.txt
python python/golden_model.py
python python/test_golden_model.py
python -m pytest python -v
```

Python 3.10+ is recommended. No third-party runtime package is required; `pytest` is optional. Software tests validate the reference algorithm only, not RTL equivalence or FPGA behavior.

## 9. Integration Items to Close Before RTL Sign-Off

1. Define how the UART response reports status for both input nibbles.
2. Freeze the exact cycle when `o_data`, `o_status`, and `o_done` are valid together.
3. Ensure UART controller waits for one TX byte to finish before starting the next.
4. Confirm each RTL reset branch follows the reset contract above.
