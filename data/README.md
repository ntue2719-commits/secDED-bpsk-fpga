# Verification Dataset — SECDED + BPSK FPGA

Deterministic, bit-exact **Python Golden Model** reference vectors for the six-stage DSP pipeline. Use these files to compare RTL outputs against expected values, including intermediate stages and LFSR states. The dataset does **not** establish cycle accuracy or prove RTL/FPGA correctness.

See [Project README](../README.md) for the overview and [Technical Specification](../docs/spec.md) for algorithms, ports, and cycle timing.

## Dataset Summary

| Property | Value |
|---|---|
| Input payloads | 16 (`0x0`–`0xF`, 4 bits each) |
| Noise levels | 8 (`0`–`7`) |
| Error modes exported | 3 (`00` none, `01` single, `10` double) |
| Total DSP transactions | **384** (`16 × 8 × 3`) |
| SECDED codeword width | 8 bits |
| BPSK symbol mapping | bit `0` → `+127`, bit `1` → `-127` |
| BPSK samples | 8 per bit × 8 bits = **64 per transaction** |
| Total samples | **24,576** per sample-stream file |
| Sample representation | Signed 8-bit, stored as two's-complement HEX |
| Error / noise LFSR reset seeds | `0xA5` / `0x01` |
| LFSR behavior | Preserve state across transactions; no automatic reseed |

Mode `11` (reserved / treated as no error) is supported by the Golden Model, but **not included** in this exported 384-transaction matrix.

## File Inventory

### Transaction-level vectors — one line per transaction (384 lines each)

| File | Signal / reference | Bits per value | Description |
|---|---|---:|---|
| `input_data.hex` | `input_data` | 4 | Input payload for encoder |
| `config.hex` | `{3'b000, noise_level[2:0], err_mode[1:0]}` | 8 | Packed transaction configuration |
| `encoded.hex` | `encoded_word` | 8 | SECDED encoded codeword |
| `corrupted.hex` | `corrupted_word` | 8 | Codeword after bit-flip injection |
| `demodulated.hex` | `received_word` | 8 | Codeword reconstructed from noisy samples |
| `decoded.hex` | `result_data` | 4 | Corrected payload, or `0` for detected double-bit error |
| `status.hex` | `status` | 2 | Decoder status (`0`, `1`, or `2`) |
| `syndrome.hex` | `syndrome` | 3 | SECDED syndrome |
| `corrected.hex` | `corrected_word` | 8 | Decoder corrected word; unchanged on double-bit detection |
| `error_lfsr_before.hex` | `error_lfsr_before` | 8 | Error LFSR state before codeword |
| `error_lfsr_after.hex` | `error_lfsr_after` | 8 | Error LFSR state after codeword |
| `noise_lfsr_before.hex` | `noise_lfsr_before` | 8 | Noise LFSR state before 64 samples |
| `noise_lfsr_after.hex` | `noise_lfsr_after` | 8 | Noise LFSR state after 64 samples |

### Sample-level vectors — 64 lines per transaction (24,576 lines each)

| File | Signal / reference | Bits per value | Description |
|---|---|---:|---|
| `bpsk_tx.hex` | `bpsk_samples` | signed 8 | Transmitted BPSK samples before noise |
| `noise_values.hex` | `noise_values` | signed 8 | Signed additive noise value for each sample |
| `bpsk_noisy.hex` | `noisy_samples` | signed 8 | Saturated sample after noise injection |

**Metadata:** `transactions.csv` has **384 data rows**, plus a header, with transaction index, payload, noise level, error mode, flipped positions, codeword intermediates, decoder output, and status. Its numeric payload/mode/status fields are decimal; several codeword/data fields are represented as hexadecimal text. The CSV is intended for debugging, not for direct `$readmemh` loading.

Each `.hex` line contains **one value**, without `0x` prefix. The generator writes 1 hexadecimal digit for 4-bit payload/status/syndrome files and 2 hexadecimal digits for 8-bit values. Signed values are masked to 8-bit two's complement: `+127 → 7F`, `-127 → 81`, `-128 → 80`, `-64 → C0`.

## Transaction and Sample Ordering

The generator uses **one** `GoldenModel()` instance for the full matrix:

```python
for data in range(16):
    for noise_level in range(8):
        for err_mode in (0, 1, 2):
            model.process(data, noise_level, err_mode)
```

Zero-based transaction index:

```text
t = data * 24 + noise_level * 3 + err_mode
```

| Transaction `t` | Payload | Noise level | Error mode |
|---:|---:|---:|---:|
| 0 | `0x0` | 0 | 0 |
| 1 | `0x0` | 0 | 1 |
| 2 | `0x0` | 0 | 2 |
| 23 | `0x0` | 7 | 2 |
| 24 | `0x1` | 0 | 0 |
| 383 | `0xF` | 7 | 2 |

The 64 sample entries for transaction `t` occupy flattened indices **`t*64` through `t*64+63`**. Samples are MSB-first: codeword bit 7 maps to offsets 0–7, bit 6 to 8–15, ..., bit 0 to 56–63.

The two LFSRs **advance across transaction boundaries**: error LFSR once per valid codeword (even mode `00`), and noise LFSR once per valid sample (even noise level 0). Each decision uses the **current/pre-update state**, followed by state advance. Independent per-transaction resets will not match this dataset.

## DSP Stage Mapping

```text
input_data.hex
    └─ hamming_encoder ─────── encoded.hex
        └─ bit_flip_channel ── corrupted.hex
            └─ bpsk_modulator ─── bpsk_tx.hex
                └─ lfsr_noise_injector ─ bpsk_noisy.hex
                    └─ bpsk_demodulator ─ demodulated.hex
                        └─ hamming_decoder ─ decoded.hex
                                              status.hex
```

`noise_values.hex`, `syndrome.hex`, `corrected.hex`, and the four LFSR files provide additional intermediate checks (some are internal/debug references, not external RTL ports).

Decoder status:

| Value | Meaning | `decoded.hex` behavior |
|---|---|---|
| `0` | No error detected | Decoded payload |
| `1` | Single-bit error corrected | Corrected payload |
| `2` | Double-bit error detected | Diagnostic zero |

## Noise Model Limitation

**Noise never causes bit errors in this configuration.** BPSK amplitudes are `±127`; the largest added noise magnitude is `64`. After saturation, transmitted positive samples remain in `[+63,+127]` and negative samples remain in `[-128,-63]`. Consequently, per-bit accumulated signs cannot change and BPSK demodulation reconstructs exactly the bit-flipped codeword.

Therefore:

- Detected/corrected SECDED errors come from **`bit_flip_channel`**, not additive noise.
- The eight noise levels exercise **LFSR sequencing, signed addition, saturation, and sample-by-sample equivalence**.
- This dataset is **not a BER-versus-SNR benchmark** and does not demonstrate decoder recovery from noise-induced bit errors.

Noise amplitude LUT: `0, 4, 8, 16, 24, 32, 48, 64` for levels `0..7`.

## Regenerating Vectors

Run from the repository root:

```bash
python python/test_golden_model.py
python python/export_hex.py
```

The exporter writes all vectors into `data/`. It also supports a custom output path:

```bash
python python/export_hex.py --output data
```

The Python Golden Model and exporter are the source of truth for **expected functional values**. Do not hand-edit generated HEX data; regenerate them whenever the model or test matrix changes.

## RTL Verification Example

```systemverilog
logic [3:0] payload_ref [0:383];
logic [7:0] encoded_ref [0:383];
logic [7:0] tx_sample_ref [0:24575];
logic [7:0] noisy_sample_ref [0:24575];
logic [3:0] decoded_ref [0:383];
logic [1:0] status_ref [0:383];

initial begin
    $readmemh("data/input_data.hex", payload_ref);
    $readmemh("data/encoded.hex", encoded_ref);
    $readmemh("data/bpsk_tx.hex", tx_sample_ref);
    $readmemh("data/bpsk_noisy.hex", noisy_sample_ref);
    $readmemh("data/decoded.hex", decoded_ref);
    $readmemh("data/status.hex", status_ref);
end
```

Use the appropriate transaction index for word-level outputs and `t*64 + sample_offset` for sample-level outputs. Compare only on the corresponding RTL `o_valid` / `o_done` cycles; observe the **cycle-accurate contracts in `docs/spec.md`**. `$readmemh` paths are relative to the simulator's working directory.

The DSP dataset contains **individual 4-bit transactions**, not packed UART packets. The UART protocol combines two DSP results (`high` then `low`) into exactly two response bytes:

```verilog
response_byte0 = {result_hi[3:0], result_lo[3:0]};
response_byte1 = {4'b0000, status_hi[1:0], status_lo[1:0]};
```

UART packet-level tests must construct these bytes from two consecutive `GoldenModel.process()` results while preserving LFSR state. The exported HEX files do not directly encode UART RX/TX timing or packets.

## Verification Boundaries

These vectors test **functional/bit-exact behavior**. End-to-end RTL equivalence, handshake correctness, cycle latency, UART framing, throughput, synthesis timing, LUT/FF usage, and FPGA measurements require separate testbenches or hardware tools. Report `PASS` for RTL only after running those checks.
