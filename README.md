# FPGA SECDED + BPSK Communication Pipeline

Deterministic, bit-exact FPGA communication datapath combining **extended Hamming SECDED (8,4)**, **BPSK modulation**, **LFSR-based bit-error injection**, and **signed additive noise**. The project uses a Python Golden Model as the bit-exact reference for staged RTL implementation and verification.

**Implementation status:** Python Golden Model, deterministic HEX vectors, all six DSP RTL modules, `tx_rx_dsp_top`, UART RX/TX, UART controller, and `fpga_top` are implemented and verified. The complete system has passed standalone DSP verification, full DSP integration verification, and black-box UART end-to-end verification against Python Golden Model vectors. Synthesis and implementation have also been completed for timing, utilization, routing, and power analysis. **The project scope is intentionally closed at RTL simulation and post-implementation analysis; FPGA board deployment is outside the final scope.**

## Architecture

The complete system flow is **UART RX → UART Controller → DSP pipeline → UART Controller → UART TX**. The figures below show the implemented `tx_rx_dsp_top.v` DSP wrapper and its six processing stages, while `fpga_top.v` integrates the UART and DSP subsystems.

### FPGA top-level interface

![External interface of fpga_top.v](docs/images/fpga_top_blackbox.jpg)

`fpga_top.v` is the board/system-level wrapper. Its external interface contains the 50 MHz system clock `i_clk`, synchronous active-low reset `i_rst_n`, serial UART receive input `i_uart_rx`, and serial UART transmit output `o_uart_tx`.

### FPGA top-level internal architecture

![Internal architecture of fpga_top.v](docs/images/fpga_top_low.jpg)

The top-level wrapper connects four main blocks: `uart_rx`, `uart_controller`, `tx_rx_dsp_top`, and `uart_tx`. The UART receiver converts the serial request into bytes, the protocol controller extracts configuration and payload information, the DSP wrapper processes the high and low nibbles sequentially, and the UART transmitter serializes the two response bytes.

The synthesizable UART configuration uses **8-N-1 at 115200 baud** with `CLKS_PER_BIT = 434` for a 50 MHz clock. During fast functional simulation, this timing parameter may be overridden without changing the UART framing or protocol behavior.

### UART controller FSM

![Twelve-state UART protocol and handshake FSM](docs/images/uart_controller_fsm.jpg)

The `uart_controller.v` block uses a 12-state finite-state machine to coordinate the complete request/response transaction. It waits for the CONFIG and DATA bytes, starts the DSP first for the high nibble and then for the low nibble, captures the independent result/status values, and finally transmits the packed result and status bytes through `uart_tx`. Handshake states explicitly wait for DSP completion and UART transmitter busy/idle transitions before advancing.

### DSP top-level interface

![Six inputs and three outputs of tx_rx_dsp_top.v](docs/images/tx_rx_dsp_top_interface.png)

| Input | Width | Output | Width |
|---|---:|---|---:|
| `i_clk` | 1 | `o_data` | 4 |
| `i_rst_n` | 1 | `o_status` | 2 |
| `i_data` | 4 | `o_done` | 1 |
| `i_noise_level` | 3 |  |  |
| `i_err_mode` | 2 |  |  |
| `i_start` | 1 |  |  |

`i_start` is accepted only while idle; requests are ignored while the DSP transaction is active. The payload and configuration are captured at acceptance. `o_done` is a one-clock **transaction-completion** pulse asserted with valid registered `o_data` and `o_status`.

All DSP modules use a **synchronous active-low reset** through `i_rst_n`.

### Six-stage DSP datapath

![SECDED encoder, error channel, BPSK modulator, noise injector, BPSK demodulator, and decoder](docs/images/tx_rx_dsp_top_architecture.png)

| Stage | RTL module | Function | Verification |
|---|---|---|---|
| 1 | `hamming_encoder.v` | Encode 4-bit payload into an 8-bit SECDED codeword | PASS |
| 2 | `bit_flip_channel.v` | Inject 0, 1, or 2 codeword-bit errors using error LFSR | PASS |
| 3 | `bpsk_modulator.v` | Produce 64 signed samples, MSB-first, eight per bit | PASS |
| 4 | `lfsr_noise_injector.v` | Add deterministic noise and saturate each sample | PASS |
| 5 | `bpsk_demodulator.v` | Correlate groups of eight samples to recover the codeword | PASS |
| 6 | `hamming_decoder.v` | Correct single-bit errors or detect double-bit errors | PASS |

Between modules, `valid` qualifies the current data item. **Sample-stream** `done` marks sample 63 in the modulator/noise stages; the **top-level** `o_done` marks the completed decoded transaction.

For full signal lists, bit widths, algorithms, reset rules, and cycle timing, see [the technical specification](docs/spec.md).

## Design Parameters

| Parameter | Frozen value |
|---|---|
| Target clock | 50 MHz (20 ns) |
| UART | 115200 baud, 8-N-1, `CLKS_PER_BIT = 434` |
| Payload / codeword | 4 / 8 bits |
| BPSK mapping | `0 → +127`, `1 → -127`; MSB-first |
| Sampling | 8 samples/bit; 64 samples/codeword |
| Sample type | Signed 8-bit, saturated to `[-128, 127]` |
| Noise amplitude levels 0–7 | `0, 4, 8, 16, 24, 32, 48, 64` |
| Error / noise LFSR reset seeds | `0xA5` / `0x01` |
| LFSR feedback | `state[7] ^ state[5] ^ state[4] ^ state[3]` |
| Demodulation decision | Correlation `>= 0` → bit `0`; `< 0` → bit `1` |

Both LFSRs use their **current states before advancing**. The error LFSR advances once per valid codeword; the noise LFSR advances once per valid sample, including noise level 0. Their states persist across consecutive transactions and reset only when `i_rst_n = 0`.

### Error modes and result status

| `i_err_mode` | Injection | Typical decoder status |
|---|---|---|
| `00` | No flipped bit | `00` (no error) |
| `01` | One bit flipped | `01` (corrected) |
| `10` | Two distinct bits flipped | `10` (detected, `o_data = 0` diagnostic) |
| `11` | Reserved; no flip | `00` (no error) |

Status indicates the **actual decoder outcome**, not merely the configured error mode. See [SPEC](docs/spec.md) for parity/syndrome rules and double-bit collision handling.

### Noise-model limitation

**The present noise settings do not produce demodulation bit errors.** A BPSK symbol is `+127` or `-127`, while noise magnitude is at most 64. After saturation, positive samples remain in `[63, 127]` and negative samples in `[-128, -63]`; therefore each eight-sample correlation preserves its original sign.

Bit errors observed downstream originate from the deliberate `bit_flip_channel`, **not** from the noise injector.

The noise path is currently used to verify:

- deterministic noise-LFSR ordering;

- signed arithmetic;

- saturation behavior;

- sample-level RTL/Python equivalence;

- sign-preserving BPSK demodulation.

The current dataset is **not** a BER-versus-SNR benchmark.

## RTL Verification Status

The current DSP core has passed **standalone self-checking testbenches for all six processing stages** and a full-pipeline integration testbench in Vivado XSim.

| Verification target | Result |
|---|---:|
| `hamming_encoder.v` standalone TB | **PASS — 69 checks, 0 errors** |
| `bit_flip_channel.v` standalone TB | **PASS — 1,537 checks, 0 errors** |
| `bpsk_modulator.v` standalone TB | **PASS** |
| `lfsr_noise_injector.v` standalone TB | **PASS** |
| `bpsk_demodulator.v` standalone TB | **PASS** |
| `hamming_decoder.v` standalone TB | **PASS — 1,954 checks, 0 errors** |
| `tx_rx_dsp_top.v` full integration TB | **PASS — 154,373 checks, 0 errors** |
| Full DSP transactions | **384 / 384 PASS** |
| BPSK/noise samples checked | **24,576** |

The integration testbench is a **white-box stage-by-stage comparison**. It checks intermediate RTL results against all available Python Golden Model HEX references, including:

- encoded codewords;

- corrupted codewords;

- error-LFSR before/after states;

- BPSK TX samples;

- noise values;

- noise-LFSR before/after states;

- noisy BPSK samples;

- demodulated codewords;

- decoder syndrome;

- corrected codewords;

- decoded payload;

- decoder status;

- top-level `o_data`, `o_status`, and `o_done`.

Latest full-pipeline XSim result:

```text

------------------------------------------------------------

tx_rx_dsp_top checks: 154373, errors: 0

Transactions: 384

BPSK/noise samples: 24576

PASS: tb_tx_rx_dsp_top

```

These results establish **functional RTL equivalence for the tested DSP dataset**. Together with the final UART end-to-end testbench, they verify the complete simulated request/response path from external UART RX through the DSP pipeline and back to external UART TX.

## UART Request/Response Contract

UART integration is implemented and verified at system level. The host-side request/response protocol is frozen in the specification.

The host sends **two bytes** per request:

```verilog

config = {3'b000, noise_level[2:0], err_mode[1:0]};

data   = {data_hi[3:0], data_lo[3:0]};

```

The controller processes **high nibble first**, then low nibble, on the same stateful DSP instance.

The FPGA returns:

```verilog

response_byte0 = {result_hi[3:0], result_lo[3:0]};

response_byte1 = {4'b0000, status_hi[1:0], status_lo[1:0]};

```

Each nibble has an independent two-bit SECDED status:

- `00` — no error;

- `01` — single-bit error corrected;

- `10` — double-bit error detected.

UART RTL and the host-side protocol are verified using the final black-box `tb_fpga_top.sv` end-to-end testbench. The testbench drives only the external UART RX input, observes the external UART TX output, and compares the returned bytes against Python Golden Model vectors.

Latest end-to-end XSim result:

```text

------------------------------------------------------------

fpga_top end-to-end requests: 96

fpga_top checks: 577, errors: 0

PASS: tb_fpga_top

```

The 96 UART requests correspond to 192 DSP nibble transactions. Fast simulation uses a parameterized UART timing value of `CLKS_PER_BIT = 8`, while the synthesizable hardware default remains `CLKS_PER_BIT = 434` for a 50 MHz clock and 115200 baud. The parameter change only scales UART bit duration in simulation; UART framing, controller behavior, DSP processing, LFSR state progression, and Golden Model comparisons remain unchanged.

## Post-Implementation Analysis

Synthesis and implementation were completed in Vivado to evaluate resource usage, routing, timing, and estimated power. These results are used as implementation-analysis evidence only; the project is not deployed to a physical FPGA board.

| Metric | Post-implementation result |
|---|---:|
| Target clock | 50 MHz (20 ns) |
| WNS | **+17.949 ns** |
| TNS | **0.000 ns** |
| WHS | **+0.039 ns** |
| THS | **0.000 ns** |
| LUT | **165** |
| FF | **213** |
| BRAM | **0** |
| URAM | **0** |
| DSP | **0** |
| Total on-chip power | **0.289 W** |
| Failed routes | **0** |

The implemented design meets the specified 50 MHz timing constraint with positive setup and hold slack. Routing completed without failed routes. Vivado reduced LUT usage from 177 after synthesis to 165 after implementation while the register count remained 213.

The reported power value is a Vivado post-implementation estimate rather than a physical-board measurement.

Methodology warnings remain associated with board-level I/O constraints. Because physical FPGA deployment is explicitly outside the final project scope, package-pin assignment, board I/O standard constraints, bitstream generation, and hardware validation are intentionally not completed.

## Quick Start

**Requirements:** Python 3.10+; the Golden Model uses the Python standard library. `pytest` is optional.

From the repository root:

```bash

python python/golden_model.py

python python/test_golden_model.py

python python/export_hex.py

# Optional

python -m pip install -r requirements.txt

python -m pytest python -v

```

Expected software output includes:

```text

PASS: all golden-model tests

PASS: HEX vectors generated and verified

Transactions: 384

BPSK samples: 24576

HEX files: 16

```

`GoldenModel` preserves both LFSR states between calls, so do not recreate it for each transaction when verifying an uninterrupted sequence.

## Verification Dataset

| Dataset property | Value |
|---|---:|
| Input payload values | 16 (`0x0`–`0xF`) |
| Noise levels | 8 |
| Error modes in exported matrix | 3 (`00`, `01`, `10`) |
| Total DSP transactions | **384** |
| BPSK TX samples | **24,576** |
| Noise samples | **24,576** |
| Noisy BPSK samples | **24,576** |
| HEX stage-reference files | **16** |
| Transaction metadata | `transactions.csv` (384 rows) |

The dataset contains transaction-level references for:

- payload and configuration;

- encoded and corrupted codewords;

- demodulated codeword;

- decoded payload and status;

- syndrome and corrected codeword;

- error/noise LFSR states before and after each transaction.

It also contains 64 sample-level values per transaction for:

- `bpsk_tx.hex`;

- `noise_values.hex`;

- `bpsk_noisy.hex`.

Signed samples are stored as 8-bit two's-complement HEX bytes.

See [data/README.md](data/README.md) for exact ordering, file definitions, and `$readmemh` usage.

## Repository Structure

```text

secDED-bpsk-fpga/

├── README.md

├── requirements.txt

│

├── docs/

│   ├── spec.md

│   └── images/

│       ├── tx_rx_dsp_top_interface.png

│       └── tx_rx_dsp_top_architecture.png

│

├── python/

│   ├── golden_model.py

│   ├── test_golden_model.py

│   └── export_hex.py

│

├── rtl/

│   ├── tx_rx_dsp_top.v

│   ├── hamming_encoder.v

│   ├── bit_flip_channel.v

│   ├── bpsk_modulator.v

│   ├── lfsr_noise_injector.v

│   ├── bpsk_demodulator.v

│   └── hamming_decoder.v

│

├── tb/

│   ├── tb_hamming_encoder.sv

│   ├── tb_bit_flip_channel.sv

│   ├── tb_bpsk_modulator.sv

│   ├── tb_lfsr_noise_injector.sv

│   ├── tb_bpsk_demodulator.sv

│   ├── tb_hamming_decoder.sv

│   └── tb_tx_rx_dsp_top.sv

│

└── data/

    ├── README.md

    ├── *.hex

    └── transactions.csv

```

## Roadmap

- [x] Python Golden Model and algorithm tests

- [x] Deterministic HEX vector export and dataset documentation

- [x] Algorithm, RTL interface, reset, and timing contracts in `docs/spec.md`

- [x] Implement six-stage SECDED + BPSK DSP RTL

- [x] Verify Hamming encoder against Golden Model

- [x] Verify deterministic bit-flip channel and error LFSR

- [x] Verify BPSK modulator with standalone self-checking testbench

- [x] Verify LFSR noise injector with standalone self-checking testbench

- [x] Verify BPSK demodulator with standalone self-checking testbench

- [x] Verify Hamming decoder exhaustively and against Golden vectors

- [x] Verify all six DSP stages independently

- [x] Verify full `tx_rx_dsp_top` stage-by-stage against all HEX references

- [ ] Implement and verify UART RX/TX and controller

- [ ] Run synthesis, implementation, timing, and resource-utilization analysis

- [ ] Validate on FPGA hardware and publish measured results

## Final Project Scope

The project is considered complete at the **RTL verification and post-implementation analysis** level.

Final verified flow:

```text

Python Golden Model

        ↓

Deterministic HEX / UART vectors

        ↓

Standalone DSP RTL verification

        ↓

Full tx_rx_dsp_top integration verification

        ↓

UART RX

        ↓

UART Controller

        ↓

SECDED + BPSK DSP pipeline

        ↓

UART Controller

        ↓

UART TX

        ↓

Black-box fpga_top end-to-end verification

        ↓

Vivado synthesis and implementation analysis

```

The final scope **does not include FPGA board programming, bitstream validation, physical UART testing, oscilloscope/logic-analyzer measurements, or measured board power**. Any future board deployment should therefore be treated as an optional extension rather than unfinished work.

**Reference documentation:** [Technical SPEC](docs/spec.md) · [Dataset Guide](data/README.md)
