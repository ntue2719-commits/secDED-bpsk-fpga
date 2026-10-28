"""Export deterministic, bit-exact SECDED/BPSK reference vectors for RTL verification.

Run from the repository root:
    python python/export_hex.py

The script generates:
1. DSP-level vectors:
   - 384 transactions
   - 16 HEX files
   - transactions.csv

2. UART-level end-to-end vectors:
   - 96 UART requests
   - 192 DSP transactions
   - 4 HEX files
   - uart_transactions.csv

Each dataset uses its own GoldenModel instance and therefore represents
an independent reset sequence. Within each dataset, all LFSR states persist
continuously across the ordered transactions.
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

ERROR_MODES = (
    ERR_MODE_NO_ERROR,
    ERR_MODE_SINGLE,
    ERR_MODE_DOUBLE,
)

DSP_TRANSACTION_COUNT = 16 * 8 * len(ERROR_MODES)

UART_DATA_PATTERNS = (
    0x00,
    0xFF,
    0xA5,
    0x5A,
)

UART_REQUEST_COUNT = 8 * len(ERROR_MODES) * len(UART_DATA_PATTERNS)
UART_DSP_TRANSACTION_COUNT = UART_REQUEST_COUNT * 2


def write_hex(path: Path, values, width: int = 2) -> None:
    """Write one unsigned hexadecimal word per line; signed values use two's complement."""
    mask = (1 << (width * 4)) - 1

    with path.open("w", encoding="ascii", newline="\n") as handle:
        for value in values:
            if not -(1 << (width * 4 - 1)) <= value <= mask:
                raise ValueError(
                    f"Value outside {width}-digit HEX range: {value}"
                )

            handle.write(f"{value & mask:0{width}X}\n")


def generate_dsp_vectors(output_dir: Path) -> None:
    """Generate the 384-transaction stage-by-stage DSP reference dataset."""
    model = GoldenModel()

    vectors = {
        name: []
        for name in (
            "input_data",
            "config",
            "encoded",
            "corrupted",
            "bpsk_tx",
            "noise_values",
            "bpsk_noisy",
            "demodulated",
            "decoded",
            "status",
            "syndrome",
            "corrected",
            "error_lfsr_before",
            "error_lfsr_after",
            "noise_lfsr_before",
            "noise_lfsr_after",
        )
    }

    transactions = []

    previous_error_state = ERROR_LFSR_SEED
    previous_noise_state = NOISE_LFSR_SEED

    for data in range(16):
        for noise_level in range(8):
            for err_mode in ERROR_MODES:
                r = model.process(
                    data,
                    noise_level,
                    err_mode,
                )

                index = len(transactions)

                # Verify continuous deterministic LFSR state.
                assert r.error_lfsr_before == previous_error_state, (
                    index,
                    "error LFSR discontinuity",
                )

                assert r.noise_lfsr_before == previous_noise_state, (
                    index,
                    "noise LFSR discontinuity",
                )

                # Verify stream lengths.
                assert len(r.bpsk_samples) == SAMPLES_PER_CODEWORD
                assert len(r.noisy_samples) == SAMPLES_PER_CODEWORD
                assert len(r.noise_values) == SAMPLES_PER_CODEWORD

                # Current noise amplitudes cannot reverse BPSK sample sign.
                assert r.received_word == r.corrupted_word, (
                    index,
                    "noise unexpectedly flipped a bit",
                )

                assert all(
                    (a >= 0) == (b >= 0)
                    for a, b in zip(
                        r.bpsk_samples,
                        r.noisy_samples,
                    )
                )

                expected_status = {
                    ERR_MODE_NO_ERROR: NO_ERROR,
                    ERR_MODE_SINGLE: SINGLE_BIT_CORRECTED,
                    ERR_MODE_DOUBLE: DOUBLE_BIT_DETECTED,
                }[err_mode]

                assert r.status == expected_status, (
                    index,
                    "unexpected decoder status",
                )

                assert r.result_data == (
                    0
                    if err_mode == ERR_MODE_DOUBLE
                    else data
                )

                config = (noise_level << 2) | err_mode

                # One value per DSP transaction.
                vectors["input_data"].append(data)
                vectors["config"].append(config)
                vectors["encoded"].append(r.encoded_word)
                vectors["corrupted"].append(r.corrupted_word)
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

                # 64 values per DSP transaction.
                vectors["bpsk_tx"].extend(r.bpsk_samples)
                vectors["noise_values"].extend(r.noise_values)
                vectors["bpsk_noisy"].extend(r.noisy_samples)

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

    assert len(transactions) == DSP_TRANSACTION_COUNT

    for name, values in vectors.items():
        if name in (
            "bpsk_tx",
            "noise_values",
            "bpsk_noisy",
        ):
            expected_count = (
                DSP_TRANSACTION_COUNT
                * SAMPLES_PER_CODEWORD
            )
        else:
            expected_count = DSP_TRANSACTION_COUNT

        assert len(values) == expected_count, (
            name,
            len(values),
        )

        write_hex(
            output_dir / f"{name}.hex",
            values,
        )

    with (
        output_dir / "transactions.csv"
    ).open(
        "w",
        newline="",
        encoding="utf-8",
    ) as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=list(transactions[0]),
        )

        writer.writeheader()
        writer.writerows(transactions)

    print("PASS: DSP HEX vectors generated and verified")
    print(f"DSP transactions: {len(transactions)}")
    print(f"BPSK samples: {len(vectors['bpsk_tx'])}")
    print(f"DSP HEX files: {len(vectors)}")


def generate_uart_vectors(output_dir: Path) -> None:
    """Generate black-box UART-level vectors for tb_fpga_top."""
    model = GoldenModel()

    uart_vectors = {
        "uart_config": [],
        "uart_data": [],
        "uart_expected_data": [],
        "uart_expected_status": [],
    }

    uart_transactions = []

    previous_error_state = ERROR_LFSR_SEED
    previous_noise_state = NOISE_LFSR_SEED

    dsp_transaction_index = 0

    for noise_level in range(8):
        for err_mode in ERROR_MODES:
            config = (noise_level << 2) | err_mode

            for data_byte in UART_DATA_PATTERNS:
                request_index = len(uart_transactions)

                data_hi = (data_byte >> 4) & 0x0F
                data_lo = data_byte & 0x0F

                # Controller contract:
                # process high nibble first.
                high = model.process(
                    data_hi,
                    noise_level,
                    err_mode,
                )

                assert high.error_lfsr_before == previous_error_state, (
                    dsp_transaction_index,
                    "UART high error LFSR discontinuity",
                )

                assert high.noise_lfsr_before == previous_noise_state, (
                    dsp_transaction_index,
                    "UART high noise LFSR discontinuity",
                )

                previous_error_state = high.error_lfsr_after
                previous_noise_state = high.noise_lfsr_after
                dsp_transaction_index += 1

                # Then process low nibble without reseeding.
                low = model.process(
                    data_lo,
                    noise_level,
                    err_mode,
                )

                assert low.error_lfsr_before == previous_error_state, (
                    dsp_transaction_index,
                    "UART low error LFSR discontinuity",
                )

                assert low.noise_lfsr_before == previous_noise_state, (
                    dsp_transaction_index,
                    "UART low noise LFSR discontinuity",
                )

                previous_error_state = low.error_lfsr_after
                previous_noise_state = low.noise_lfsr_after
                dsp_transaction_index += 1

                expected_status = {
                    ERR_MODE_NO_ERROR: NO_ERROR,
                    ERR_MODE_SINGLE: SINGLE_BIT_CORRECTED,
                    ERR_MODE_DOUBLE: DOUBLE_BIT_DETECTED,
                }[err_mode]

                assert high.status == expected_status
                assert low.status == expected_status

                assert high.result_data == (
                    0
                    if err_mode == ERR_MODE_DOUBLE
                    else data_hi
                )

                assert low.result_data == (
                    0
                    if err_mode == ERR_MODE_DOUBLE
                    else data_lo
                )

                # FPGA -> Host response byte 0:
                # {result_hi[3:0], result_lo[3:0]}
                response_data = (
                    (high.result_data << 4)
                    | low.result_data
                )

                # FPGA -> Host response byte 1:
                # {4'b0000, status_hi[1:0], status_lo[1:0]}
                response_status = (
                    (high.status << 2)
                    | low.status
                )

                uart_vectors["uart_config"].append(config)
                uart_vectors["uart_data"].append(data_byte)
                uart_vectors["uart_expected_data"].append(
                    response_data
                )
                uart_vectors["uart_expected_status"].append(
                    response_status
                )

                uart_transactions.append({
                    "request_index": request_index,
                    "config": config,
                    "noise_level": noise_level,
                    "err_mode": err_mode,
                    "data_byte": data_byte,
                    "data_hi": data_hi,
                    "data_lo": data_lo,
                    "result_hi": high.result_data,
                    "result_lo": low.result_data,
                    "status_hi": high.status,
                    "status_lo": low.status,
                    "response_data": response_data,
                    "response_status": response_status,
                })

    assert len(uart_transactions) == UART_REQUEST_COUNT
    assert dsp_transaction_index == UART_DSP_TRANSACTION_COUNT

    for name, values in uart_vectors.items():
        assert len(values) == UART_REQUEST_COUNT, (
            name,
            len(values),
        )

        write_hex(
            output_dir / f"{name}.hex",
            values,
        )

    with (
        output_dir / "uart_transactions.csv"
    ).open(
        "w",
        newline="",
        encoding="utf-8",
    ) as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=list(uart_transactions[0]),
        )

        writer.writeheader()
        writer.writerows(uart_transactions)

    print("PASS: UART HEX vectors generated and verified")
    print(f"UART requests: {len(uart_transactions)}")
    print(
        "UART DSP transactions: "
        f"{dsp_transaction_index}"
    )
    print(f"UART HEX files: {len(uart_vectors)}")


def generate_vectors(output_dir: Path = OUTPUT_DIR) -> None:
    """Generate all DSP-level and UART-level verification vectors."""
    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    generate_dsp_vectors(output_dir)
    generate_uart_vectors(output_dir)

    print("------------------------------------------------------------")
    print("PASS: all verification vectors generated")
    print(f"Total HEX files: {16 + 4}")
    print("CSV files: 2")
    print(f"Output: {output_dir}")


if __name__ == "__main__":
    generate_vectors()
