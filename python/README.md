# Python Golden Model and Reference Vector Generator

This directory contains the software reference model used to verify the FPGA SECDED + BPSK RTL implementation.

The Python flow provides:

- a stateful, bit-exact Golden Model;
- algorithm-level self-tests;
- deterministic DSP reference vectors;
- deterministic UART end-to-end reference vectors;
- HEX files for `$readmemh`;
- CSV transaction logs for debugging and inspection.

The Python implementation uses only the Python standard library. `pytest` is optional.

---

## Files

```text
python/
├── golden_model.py
├── test_golden_model.py
└── export_hex.py
```

### `golden_model.py`

Implements the reference SECDED + BPSK processing chain:

```text
4-bit payload
    ->
SECDED (8,4) encoder
    ->
deterministic bit-flip channel
    ->
BPSK modulator
    ->
deterministic LFSR noise injector
    ->
BPSK demodulator
    ->
SECDED decoder
```

The model is **stateful**. The error LFSR and noise LFSR are preserved between consecutive calls to `GoldenModel.process()`.

Frozen parameters:

| Parameter | Value |
|---|---|
| Payload width | 4 bits |
| SECDED codeword | 8 bits |
| BPSK mapping | `0 -> +127`, `1 -> -127` |
| Samples per bit | 8 |
| Samples per codeword | 64 |
| Error LFSR seed | `0xA5` |
| Noise LFSR seed | `0x01` |
| LFSR polynomial | `x^8 + x^6 + x^5 + x^4 + 1` |
| LFSR feedback | `state[7] ^ state[5] ^ state[4] ^ state[3]` |
| Noise levels | `0, 4, 8, 16, 24, 32, 48, 64` |
| Sample saturation | `[-128, +127]` |
| Demodulation | `sum >= 0 -> 0`, `sum < 0 -> 1` |

Error modes:

```text
0 -> no error
1 -> single-bit error
2 -> double-bit error
3 -> reserved, treated as no error
```

For a detected double-bit error:

```text
data   = 0
status = 2
```

---

## Requirements

Recommended:

```text
Python 3.10+
```

No third-party package is required for the normal flow.

Check Python:

```bash
python --version
```

On Linux/macOS, if necessary:

```bash
python3 --version
```

Optional `pytest` installation:

```bash
python -m pip install pytest
```

---

## Recommended Repository Layout

Run the scripts from the repository root:

```text
project_root/
├── python/
│   ├── golden_model.py
│   ├── test_golden_model.py
│   └── export_hex.py
│
└── data/
```

The `data/` directory is created automatically by `export_hex.py`.

---

## 1. Run the Golden Model Demo

From the repository root:

```bash
python python/golden_model.py
```

The script creates one `GoldenModel` instance and processes example transactions using:

```text
data        = 0xA
noise_level = 0
err_mode    = 0, 1, 2
```

Example output format:

```text
input=A encoded=0x.. corrupted=0x.. received=0x.. result=A status=0 syndrome=0 flips=()
input=A encoded=0x.. corrupted=0x.. received=0x.. result=A status=1 syndrome=.. flips=(..,)
input=A encoded=0x.. corrupted=0x.. received=0x.. result=0 status=2 syndrome=.. flips=(.., ..)
```

The exact corrupted codeword and flipped positions depend on the current persistent LFSR state.

---

## 2. Run the Golden Model Self-Tests

Run:

```bash
python python/test_golden_model.py
```

Expected final output:

```text
PASS: all golden-model tests
```

The self-test covers:

- all 16 SECDED payload values;
- exhaustive single-bit SECDED correction;
- all double-bit combinations for each payload;
- all 256 BPSK codewords;
- zero-noise behavior;
- all eight noise levels;
- saturation boundaries;
- current-state LFSR semantics;
- reserved error mode;
- noise sign preservation;
- the full 384-transaction DSP matrix;
- persistent LFSR evolution;
- reset determinism.

A failure raises `AssertionError`.

### Optional pytest flow

```bash
python -m pytest python/test_golden_model.py -v
```

or:

```bash
python -m pytest python -v
```

`pytest` is optional. The test script can be executed directly.

---

## 3. Generate RTL Reference Vectors

Run:

```bash
python python/export_hex.py
```

The script creates:

```text
data/
```

and generates two independent datasets:

1. DSP-level reference vectors
2. UART-level end-to-end vectors

The DSP dataset and UART dataset each start from fresh Golden Model reset seeds.

Within each dataset, LFSR states remain continuous across all ordered transactions.

---

## Expected Export Summary

Expected console output:

```text
PASS: DSP HEX vectors generated and verified
DSP transactions: 384
BPSK samples: 24576
DSP HEX files: 16

PASS: UART HEX vectors generated and verified
UART requests: 96
UART DSP transactions: 192
UART HEX files: 4

------------------------------------------------------------
PASS: all verification vectors generated
Total HEX files: 20
CSV files: 2
Output: .../data
```

---

## 4. DSP Reference Dataset

Coverage:

```text
16 payload values
x 8 noise levels
x 3 error modes
= 384 transactions
```

Exported modes:

```text
00 -> no error
01 -> single-bit error
10 -> double-bit error
```

Reserved mode `11` is not exported in the 384-transaction matrix.

Each transaction generates:

```text
8 codeword bits x 8 samples/bit = 64 samples
```

Therefore:

```text
384 x 64 = 24,576 samples
```

### DSP HEX files

```text
data/input_data.hex
data/config.hex
data/encoded.hex
data/corrupted.hex
data/bpsk_tx.hex
data/noise_values.hex
data/bpsk_noisy.hex
data/demodulated.hex
data/decoded.hex
data/status.hex
data/syndrome.hex
data/corrected.hex
data/error_lfsr_before.hex
data/error_lfsr_after.hex
data/noise_lfsr_before.hex
data/noise_lfsr_after.hex
```

The three sample-level files:

```text
bpsk_tx.hex
noise_values.hex
bpsk_noisy.hex
```

contain `24,576` values each.

Signed values are stored as 8-bit two's-complement HEX.

Examples:

```text
+127 -> 7F
-1   -> FF
-64  -> C0
-127 -> 81
-128 -> 80
```

### DSP CSV

Generated file:

```text
data/transactions.csv
```

Columns:

```text
index
data
noise_level
err_mode
config
encoded
corrupted
received
decoded
status
syndrome
flipped_positions
```

---

## 5. UART End-to-End Dataset

UART input-byte patterns:

```text
0x00
0xFF
0xA5
0x5A
```

Coverage:

```text
8 noise levels
x 3 error modes
x 4 data patterns
= 96 UART requests
```

Each request contains two DSP nibbles:

```text
96 requests x 2 = 192 DSP transactions
```

Processing order:

```text
high nibble first
low nibble second
```

The same stateful Golden Model instance is used continuously for all 192 DSP transactions in the UART dataset.

### UART HEX files

```text
data/uart_config.hex
data/uart_data.hex
data/uart_expected_data.hex
data/uart_expected_status.hex
```

Each contains `96` values.

Request packing:

```verilog
config = {3'b000, noise_level[2:0], err_mode[1:0]};
data   = {data_hi[3:0], data_lo[3:0]};
```

Expected response packing:

```verilog
response_data =
    {result_hi[3:0], result_lo[3:0]};

response_status =
    {4'b0000, status_hi[1:0], status_lo[1:0]};
```

### UART CSV

Generated file:

```text
data/uart_transactions.csv
```

Columns:

```text
request_index
config
noise_level
err_mode
data_byte
data_hi
data_lo
result_hi
result_lo
status_hi
status_lo
response_data
response_status
```

---

## 6. Complete Python Workflow

From the repository root:

```bash
python python/golden_model.py
python python/test_golden_model.py
python python/export_hex.py
```

Recommended order:

```text
1. Run Golden Model demo
2. Run all software tests
3. Export deterministic reference vectors
4. Run standalone RTL testbenches
5. Run tx_rx_dsp_top integration testbench
6. Run fpga_top UART end-to-end testbench
```

Do not use newly generated RTL references if the software tests fail.

---

## 7. Important Stateful-Model Rule

Correct continuous use:

```python
model = GoldenModel()

r0 = model.process(...)
r1 = model.process(...)
r2 = model.process(...)
```

Do not recreate the model for every transaction:

```python
r0 = GoldenModel().process(...)
r1 = GoldenModel().process(...)
r2 = GoldenModel().process(...)
```

The second form resets the LFSRs before each transaction and does not reproduce the intended RTL sequence.

Use:

```python
model.reset()
```

only when the corresponding RTL sequence is also reset.

---

## 8. LFSR Update Semantics

The current state is used before advancing.

Error channel:

```text
current error-LFSR state
    ->
select error position(s)
    ->
process codeword
    ->
advance once
```

Noise channel:

```text
current noise-LFSR state
    ->
select noise sign
    ->
add and saturate sample
    ->
advance once
```

The noise LFSR advances once per valid sample even when:

```text
noise_level = 0
```

This behavior is part of the frozen Python/RTL contract.

---

## 9. Noise-Model Limitation

Maximum noise magnitude:

```text
64
```

BPSK symbols:

```text
+127
-127
```

Therefore:

```text
+127 - 64 = +63
-127 + 64 = -63
```

The configured noise cannot independently reverse sample polarity.

The current dataset verifies:

- LFSR sequencing;
- signed arithmetic;
- saturation;
- sample ordering;
- Python/RTL equivalence;
- deterministic demodulation.

It is not an AWGN model and is not a BER-vs-SNR benchmark.

---

## 10. Common Problems

### `ModuleNotFoundError: No module named 'golden_model'`

Make sure the three scripts are inside the same `python/` directory and run:

```bash
python python/test_golden_model.py
```

or:

```bash
python python/export_hex.py
```

from the repository root.

### `AssertionError`

Run:

```bash
python python/test_golden_model.py
```

and inspect the first failing assertion.

Do not regenerate production reference vectors until all tests pass.

### Old HEX files appear unchanged

`export_hex.py` writes to:

```text
<repository-root>/data/
```

Check that you are inspecting the correct directory.

### Wrong LFSR sequence

Verify that:

- one `GoldenModel` instance is reused across a continuous dataset;
- error LFSR starts at `0xA5`;
- noise LFSR starts at `0x01`;
- current state is used before advancing;
- error LFSR advances once per codeword;
- noise LFSR advances once per valid sample.

---

## 11. Expected Final Software Status

Before using the vectors for RTL verification, expect:

```text
PASS: all golden-model tests

PASS: DSP HEX vectors generated and verified
DSP transactions: 384
BPSK samples: 24576
DSP HEX files: 16

PASS: UART HEX vectors generated and verified
UART requests: 96
UART DSP transactions: 192
UART HEX files: 4

PASS: all verification vectors generated
Total HEX files: 20
CSV files: 2
```

After these checks pass, the generated files in `data/` are the deterministic software references for RTL verification.
