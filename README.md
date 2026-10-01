# FPGA SECDED + BPSK Communication Pipeline

A deterministic communication pipeline for studying error-control coding, digital modulation, noise injection, RTL design, and software-reference verification.

**Current status:** Python Golden Model and software tests are implemented. Verilog RTL, RTL-vs-Python co-verification, synthesis, and board validation are planned work; this repository does not claim hardware validation.

## System Overview

```text
4-bit payload
    |
    v
Hamming SECDED Encoder (8,4)
    |
    v
Deterministic Bit-Error Injection
    |
    v
BPSK Modulator (8 samples/bit)
    |
    v
LFSR Noise Injector
    |
    v
BPSK Demodulator
    |
    v
Hamming SECDED Decoder
    |
    v
4-bit result + 2-bit status
```

## Quick Start

Requirements: Python 3.10+. The Golden Model uses only the Python standard library; `pytest` is optional.

```bash
git clone <YOUR_REPOSITORY_URL>
cd secDED-bpsk-fpga

python -m pip install -r requirements.txt
python python/golden_model.py
python python/test_golden_model.py

# Optional test runner
python -m pytest python -v
```

Expected test result:

```text
PASS: all golden-model tests
```

## Example

```python
from python.golden_model import GoldenModel

model = GoldenModel()
r = model.process(data=0xA, noise_level=2, err_mode=1)

print(f"Encoded  : 0x{r.encoded_word:02X}")
print(f"Corrupted: 0x{r.corrupted_word:02X}")
print(f"Received : 0x{r.received_word:02X}")
print(f"Result   : 0x{r.result_data:X}")
print(f"Status   : {r.status}")
```

Use one `GoldenModel` instance for consecutive transactions. The LFSR states persist across transactions, matching the intended hardware behavior. Create a new instance only when modeling reset.

## Frozen Parameters

| Parameter | Value |
|---|---|
| Clock target | 50 MHz |
| UART | 115200 baud, 8-N-1 |
| UART clocks/bit | 434 |
| Payload / codeword | 4 bits / 8 bits |
| BPSK samples/bit | 8 (64 samples/codeword) |
| BPSK mapping | `0 → +127`, `1 → -127` |
| Error LFSR reset seed | `0xA5` |
| Noise LFSR reset seed | `0x01` |
| LFSR polynomial | `x^8 + x^6 + x^5 + x^4 + 1` |
| Noise amplitudes | `{0, 4, 8, 16, 24, 32, 48, 64}` |
| Sample saturation | `[-128, +127]` |
| Demodulation threshold | `0` |
| Bit order | MSB-first |

## Error Modes

| `err_mode` | Behavior |
|---|---|
| `00` | No injected bit error |
| `01` | Single-bit error at `error_lfsr[2:0]` |
| `10` | Double-bit error at `error_lfsr[2:0]` and `[5:3]` |
| `11` | Reserved; treated as no error |

For a double-bit position collision, the second position becomes `(pos2 + 1) mod 8`. The error LFSR advances once per codeword for every mode. The noise LFSR advances once per valid sample, including noise level zero. Neither LFSR is reseeded between normal transactions.

## Decoder Status

| Status | Meaning |
|---|---|
| `00` | No error detected |
| `01` | Single-bit error corrected |
| `10` | Double-bit error detected; `data=0` is diagnostic only |

## Repository Layout

```text
.
├── README.md
├── requirements.txt
├── docs/
│   └── spec.md
└── python/
    ├── golden_model.py
    └── test_golden_model.py
```

See [`docs/spec.md`](docs/spec.md) for the software algorithms, hardware module list, complete signal tables, reset behavior, and verification plan.

## Verification Coverage

- 16 encoder inputs
- 16 no-error decoder cases
- 128 single-bit error cases
- 448 double-bit cases (16 payloads × 28 bit pairs)
- All 256 possible BPSK codewords
- Noise levels 0–7 and saturation boundaries
- LFSR advancement and reserved error mode
- 384-case full-DSP matrix (16 payloads × 8 noise levels × 3 useful error modes)

These tests validate the Python reference only. They do not prove RTL equivalence, FPGA timing, resource utilization, or board behavior.

## Roadmap

- [x] Python Golden Model
- [x] Directed and exhaustive software tests
- [x] Frozen algorithm and interface specification
- [ ] Verilog RTL modules
- [ ] Module-level RTL testbenches
- [ ] RTL-versus-Python co-verification
- [ ] UART system test
- [ ] FPGA synthesis/resource report
- [ ] Board demonstration and measured results

## License

Choose and add a license before publishing this repository publicly.
