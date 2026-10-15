"""Export deterministic, bit-exact SECDED/BPSK reference vectors for RTL verification.

Run from the repository root: python python/export_hex.py
All LFSR states persist across the ordered 384 transactions.
"""

from pathlib import Path
import csv

from golden_model import (
    GoldenModel,
    ERROR_LFSR_SEED,
    NOISE_LFSR_SEED,
    ERR_MODE_NO_ERROR,
    ERR_MODE_SINGLE,
    ERR_MODE_DOUBLE,
    NO_ERROR,
    SINGLE_BIT_CORRECTED,
    DOUBLE_BIT_DETECTED,
    SAMPLES_PER_CODEWORD,
)

ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = ROOT / "data"
ERROR_MODES = (ERR_MODE_NO_ERROR, ERR_MODE_SINGLE, ERR_MODE_DOUBLE)
TRANSACTION_COUNT = 16 * 8 * len(ERROR_MODES)


def write_hex(path: Path, values, width: int = 2) -> None:
    """Write one unsigned hexadecimal word per line; signed 8-bit uses two's complement."""
    mask = (1 << (width * 4)) - 1
    with path.open("w", encoding="ascii", newline="\n") as handle:
        for value in values:
            if not -(1 << (width * 4 - 1)) <= value <= mask:
                raise ValueError(f"Value outside {width}-digit HEX range: {value}")
            handle.write(f"{value & mask:0{width}X}\n")


def generate_vectors(output_dir: Path = OUTPUT_DIR) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    model = GoldenModel()
    vectors = {name: [] for name in (
        "input_data", "config", "encoded", "corrupted", "bpsk_tx",
        "noise_values", "bpsk_noisy", "demodulated", "decoded",
        "status", "syndrome", "corrected", "error_lfsr_before",
        "error_lfsr_after", "noise_lfsr_before", "noise_lfsr_after",
    )}
    transactions = []
    previous_error_state = ERROR_LFSR_SEED
    previous_noise_state = NOISE_LFSR_SEED

    for data in range(16):
        for noise_level in range(8):
            for err_mode in ERROR_MODES:
                r = model.process(data, noise_level, err_mode)
                index = len(transactions)
                assert r.error_lfsr_before == previous_error_state, (index, "error LFSR discontinuity")
                assert r.noise_lfsr_before == previous_noise_state, (index, "noise LFSR discontinuity")
                assert len(r.bpsk_samples) == SAMPLES_PER_CODEWORD
                assert len(r.noisy_samples) == SAMPLES_PER_CODEWORD
                assert len(r.noise_values) == SAMPLES_PER_CODEWORD
                assert r.received_word == r.corrupted_word, (index, "noise unexpectedly flipped a bit")
                assert all((a >= 0) == (b >= 0) for a, b in zip(r.bpsk_samples, r.noisy_samples))

                expected_status = {
                    ERR_MODE_NO_ERROR: NO_ERROR,
                    ERR_MODE_SINGLE: SINGLE_BIT_CORRECTED,
                    ERR_MODE_DOUBLE: DOUBLE_BIT_DETECTED,
                }[err_mode]
                assert r.status == expected_status, (index, "unexpected decoder status")
                assert r.result_data == (0 if err_mode == ERR_MODE_DOUBLE else data)

                config = (noise_level << 2) | err_mode
                vectors["input_data"].append(data)
                vectors["config"].append(config)
                vectors["encoded"].append(r.encoded_word)
                vectors["corrupted"].append(r.corrupted_word)
                vectors["bpsk_tx"].extend(r.bpsk_samples)
                vectors["noise_values"].extend(r.noise_values)
                vectors["bpsk_noisy"].extend(r.noisy_samples)
                vectors["demodulated"].append(r.received_word)
                vectors["decoded"].append(r.result_data)
                vectors["status"].append(r.status)
                vectors["syndrome"].append(r.syndrome)
                vectors["corrected"].append(r.corrected_word)
                vectors["error_lfsr_before"].append(r.error_lfsr_before)
                vectors["error_lfsr_after"].append(r.error_lfsr_after)
                vectors["noise_lfsr_before"].append(r.noise_lfsr_before)
                vectors["noise_lfsr_after"].append(r.noise_lfsr_after)
                previous_error_state = r.error_lfsr_after
                previous_noise_state = r.noise_lfsr_after

                transactions.append({
                    "index": index,
                    "data": data,
                    "noise_level": noise_level,
                    "err_mode": err_mode,
                    "config": config,
                    "encoded": r.encoded_word,
                    "corrupted": r.corrupted_word,
                    "received": r.received_word,
                    "decoded": r.result_data,
                    "status": r.status,
                    "syndrome": r.syndrome,
                    "flipped_positions": str(r.flipped_positions),
                })

    assert len(transactions) == TRANSACTION_COUNT
    for name, values in vectors.items():
        expected_count = TRANSACTION_COUNT * SAMPLES_PER_CODEWORD if name in (
            "bpsk_tx", "noise_values", "bpsk_noisy"
        ) else TRANSACTION_COUNT
        assert len(values) == expected_count, (name, len(values))
        write_hex(output_dir / f"{name}.hex", values)

    with (output_dir / "transactions.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(transactions[0]))
        writer.writeheader()
        writer.writerows(transactions)

    print("PASS: HEX vectors generated and verified")
    print(f"Transactions: {len(transactions)}")
    print(f"BPSK samples: {len(vectors['bpsk_tx'])}")
    print(f"HEX files: {len(vectors)}")
    print(f"Output: {output_dir}")


if __name__ == "__main__":
    generate_vectors()
