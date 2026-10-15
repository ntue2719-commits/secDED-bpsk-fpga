# FPGA SECDED + BPSK Communication Pipeline

Deterministic, bit-exact reference design for an FPGA communication datapath combining **extended Hamming SECDED (8,4)**, **BPSK modulation**, **LFSR-based bit-error injection**, and **signed additive noise**. The project is structured for staged Verilog implementation and Python-to-RTL verification.

**Implementation status:** Python Golden Model, software tests, and deterministic HEX test-vector generation are implemented. **RTL design, RTL co-verification, FPGA synthesis, and board-level results are planned**; no hardware performance or correctness claims are made here.

## Architecture

The intended board-level flow is **UART RX → UART Controller → DSP pipeline → UART Controller → UART TX**. The following figures show only the `tx_rx_dsp_top.v` DSP wrapper and its internal processing stages; UART is outside this block.

### DSP top-level interface

![Six inputs and three outputs of tx_rx_dsp_top.v](docs/images/tx_rx_dsp_top_interface.png)

| Input | Width | Output | Width |
|---|---:|---|---:|
| `i_clk` | 1 | `o_data` | 4 |
| `i_rst_n` | 1 | `o_status` | 2 |
| `i_data` | 4 | `o_done` | 1 |
| `i_noise_level` | 3 | | |
| `i_err_mode` | 2 | | |
| `i_start` | 1 | | |

`i_start` is accepted only while idle; other requests are ignored while busy. The payload and configuration are captured at acceptance. `o_done` is a one-clock **transaction completion** pulse asserted with valid, registered `o_data` and `o_status`.

### Six-stage DSP datapath

![SECDED encoder, error channel, BPSK modulator, noise injector, BPSK demodulator, and decoder](docs/images/tx_rx_dsp_top_architecture.png)

| Stage | Planned RTL module | Function |
|---|---|---|
| 1 | `hamming_encoder.v` | Encode 4-bit payload into an 8-bit SECDED codeword |
| 2 | `bit_flip_channel.v` | Inject 0, 1, or 2 codeword-bit errors using error LFSR |
| 3 | `bpsk_modulator.v` | Produce 64 signed samples, MSB-first, eight per bit |
| 4 | `lfsr_noise_injector.v` | Add deterministic noise and saturate each sample |
| 5 | `bpsk_demodulator.v` | Correlate groups of eight samples to recover the codeword |
| 6 | `hamming_decoder.v` | Correct single-bit errors or detect double-bit errors |

Between modules, `valid` qualifies the current data item. **Sample-stream** `o_done` marks sample 63 in the modulator/noise stage; the **top-level** `o_done` instead marks the decoded transaction result. For signal-level descriptions, port widths, algorithms, and cycle timing, see [the technical specification](docs/spec.md).

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

Both LFSRs use their **current states before advancing**. The error LFSR advances once per valid codeword; the noise LFSR advances once per valid sample, including noise level 0. Their states persist across consecutive transactions and reset only on system reset.

### Error modes and result status

| `i_err_mode` | Injection | Typical decoder status |
|---|---|---|
| `00` | No flipped bit | `00` (no error) |
| `01` | One bit flipped | `01` (corrected) |
| `10` | Two distinct bits flipped | `10` (detected, `o_data = 0` diagnostic) |
| `11` | Reserved; no flip | `00` (no error) |

Status indicates the **actual decoder outcome**, not merely the configured error mode. See [SPEC](docs/spec.md) for parity/syndrome rules and double-bit collision handling.

### Noise-model limitation

**The present noise settings do not produce demodulation bit errors.** A BPSK symbol is `+127` or `-127`, while noise magnitude is at most 64. After saturation, positive samples remain in `[63, 127]` and negative samples in `[-128, -63]`; hence each eight-sample correlation retains its original sign. Bit errors observed downstream result from the deliberate `bit_flip_channel`, **not** the noise injector.

The noise cases test **LFSR ordering, signed arithmetic, saturation, sample-level equivalence, and sign-preserving demodulation**. The current dataset is **not** a BER-versus-SNR benchmark.

## UART Request/Response Contract (Planned RTL)

The host sends **two bytes** per request:

```verilog
config = {3'b000, noise_level[2:0], err_mode[1:0]};
data   = {data_hi[3:0], data_lo[3:0]};
```

The controller processes **high nibble first**, then low nibble, on the *same* stateful DSP instance. It returns **two bytes**:

```verilog
response_byte0 = {result_hi[3:0], result_lo[3:0]};
response_byte1 = {4'b0000, status_hi[1:0], status_lo[1:0]};
```

Each nibble has its own two-bit SECDED status (`00` no error; `01` corrected; `10` detected double error). No UART RX queue is provided during active processing/transmission. Before sending the second response byte, the controller waits for UART TX busy to **assert and then deassert**. The host-side implementation must follow this revised two-byte format; UART behavior is an RTL contract, not yet demonstrated in hardware.

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

The existing test script prints `PASS: all golden-model tests` when its checks pass. `export_hex.py` generates vectors in `data/`. The `GoldenModel` object preserves LFSR state between calls, so do not recreate it for each transaction when checking an uninterrupted sequence.

## Verification Dataset

| Dataset property | Value |
|---|---:|
| Input payload values | 16 (`0x0`–`0xF`) |
| Noise levels | 8 |
| Error modes in exported matrix | 3 (`00`, `01`, `10`) |
| Total DSP transactions | **384** |
| BPSK TX / noisy samples | **24,576 each** |
| HEX stage-reference files | **16** |
| Transaction metadata | `transactions.csv` (384 rows) |

One entry per transaction is exported for payload, config, encoded/corrupted/received codeword, decoded payload, status, syndrome, corrected codeword, and LFSR before/after states. BPSK TX, noise values, and noisy samples each have **64 entries per transaction**, stored as signed 8-bit two's-complement HEX bytes. See [data/README.md](data/README.md) for exact file names, ordering, and `$readmemh` usage.

Python test coverage additionally includes exhaustive Hamming one-bit/two-bit positions, all 256 possible BPSK codewords, LFSR checks, and noise saturation. **Software tests and HEX vectors are expected reference outputs, not proof of RTL correctness.**

## Repository Structure

```text
secDED-bpsk-fpga/
├── README.md
├── requirements.txt
├── docs/
│   ├── spec.md
│   └── images/
│       ├── tx_rx_dsp_top_interface.png
│       └── tx_rx_dsp_top_architecture.png
├── python/
│   ├── golden_model.py
│   ├── test_golden_model.py
│   └── export_hex.py
└── data/
    ├── README.md
    ├── *.hex
    └── transactions.csv
```

## Roadmap

- [x] Python Golden Model and algorithm tests
- [x] Deterministic HEX vector export and dataset documentation
- [x] Algorithm, RTL interface, and timing contracts in `docs/spec.md`
- [ ] Implement Verilog RTL and module-level self-checking testbenches
- [ ] Verify RTL against stage-by-stage Python HEX vectors
- [ ] Implement and test UART controller plus host protocol
- [ ] Run synthesis, timing, and resource utilization analysis
- [ ] Validate on FPGA hardware and publish measured results

**Reference documentation:** [Technical SPEC](docs/spec.md) · [Dataset Guide](data/README.md)
