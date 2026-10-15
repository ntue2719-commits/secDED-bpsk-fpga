
from pathlib import Path
import csv

from golden_model import (
    GoldenModel,
    ERR_MODE_NO_ERROR,
    ERR_MODE_SINGLE,
    ERR_MODE_DOUBLE,
)

ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = ROOT / "data"

ERROR_MODES = (
    ERR_MODE_NO_ERROR,
    ERR_MODE_SINGLE,
    ERR_MODE_DOUBLE,
)


def write_hex(path, values, width=2):
    with path.open("w", encoding="ascii") as f:
        for value in values:
            f.write(f"{value & ((1 << (width * 4)) - 1):0{width}X}\n")


def generate_vectors():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    model = GoldenModel()

    vectors = {
        "input_data": [],
        "config": [],
        "encoded": [],
        "corrupted": [],
        "bpsk_tx": [],
        "noise_values": [],
        "bpsk_noisy": [],
        "demodulated": [],
        "decoded": [],
        "status": [],
        "syndrome": [],
        "corrected": [],
        "error_lfsr_before": [],
        "error_lfsr_after": [],
        "noise_lfsr_before": [],
        "noise_lfsr_after": [],
    }

    transactions = []

    for data in range(16):
        for noise_level in range(8):
            for err_mode in ERROR_MODES:
                r = model.process(
                    data=data,
                    noise_level=noise_level,
                    err_mode=err_mode,
                )

                config = (
                    (noise_level << 2) | err_mode
                )

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

                vectors["error_lfsr_before"].append(
                    r.error_lfsr_before
                )
                vectors["error_lfsr_after"].append(
                    r.error_lfsr_after
                )
                vectors["noise_lfsr_before"].append(
                    r.noise_lfsr_before
                )
                vectors["noise_lfsr_after"].append(
                    r.noise_lfsr_after
                )

                transactions.append({
                    "index": len(transactions),
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
                    "flipped_positions": str(
                        r.flipped_positions
                    ),
                })

    for name, values in vectors.items():
        write_hex(
            OUTPUT_DIR / f"{name}.hex",
            values,
        )

    with (OUTPUT_DIR / "transactions.csv").open(
        "w", newline="", encoding="utf-8"
    ) as f:
        writer = csv.DictWriter(
            f,
            fieldnames=list(transactions[0].keys()),
        )
        writer.writeheader()
        writer.writerows(transactions)

    print("PASS: HEX vectors generated")
    print(f"Transactions: {len(transactions)}")
    print(f"BPSK samples: {len(vectors['bpsk_tx'])}")
    print(f"Output: {OUTPUT_DIR}")


if __name__ == "__main__":
    generate_vectors()
