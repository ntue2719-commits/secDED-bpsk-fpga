"""
Golden Model: FPGA SECDED + BPSK Communication Pipeline
Reference implementation for RTL verification.

Frozen specification:
- Input data: 4-bit
- SECDED Hamming (8,4)
- BPSK: 8 samples/bit, MSB-first
- BPSK 0 -> +127, 1 -> -127
- Error LFSR seed: 0xA5
- Noise LFSR seed: 0x01
- LFSR polynomial: x^8 + x^6 + x^5 + x^4 + 1
- Noise LUT: {0,4,8,16,24,32,48,64}
- Noise output saturates to signed 8-bit [-128,127]
- Demod threshold: 0
- err_mode 0/1/2 = no/single/double error
- err_mode 3 = reserved, treated as no error
- Double-error decode result: data=0, status=2
"""

from dataclasses import dataclass
from typing import List, Tuple

ERROR_LFSR_SEED = 0xA5
NOISE_LFSR_SEED = 0x01

NO_ERROR = 0
SINGLE_BIT_CORRECTED = 1
DOUBLE_BIT_DETECTED = 2

ERR_MODE_NO_ERROR = 0
ERR_MODE_SINGLE = 1
ERR_MODE_DOUBLE = 2
ERR_MODE_RESERVED = 3

NOISE_AMPLITUDE = (0, 4, 8, 16, 24, 32, 48, 64)
SAMPLES_PER_BIT = 8
BITS_PER_CODEWORD = 8
SAMPLES_PER_CODEWORD = 64


def _check_u8(x: int) -> int:
    if not 0 <= x <= 0xFF:
        raise ValueError(f"expected 8-bit unsigned value, got {x}")
    return x


def _check_data4(x: int) -> int:
    if not 0 <= x <= 0xF:
        raise ValueError(f"expected 4-bit data, got {x}")
    return x


def _check_noise_level(level: int) -> int:
    if not 0 <= level <= 7:
        raise ValueError(f"noise_level must be 0..7, got {level}")
    return level


def _check_err_mode(mode: int) -> int:
    if not 0 <= mode <= 3:
        raise ValueError(f"err_mode must be 0..3, got {mode}")
    return mode


def signed8(x: int) -> int:
    """Interpret an integer as an 8-bit two's-complement value."""
    x &= 0xFF
    return x - 256 if x & 0x80 else x


def saturate_signed8(x: int) -> int:
    """Saturate to the RTL sample range [-128, +127]."""
    return max(-128, min(127, x))


def lfsr_next(state: int, zero_seed: int) -> int:
    """
    One LFSR step.

    feedback = state[7] ^ state[5] ^ state[4] ^ state[3]
    next     = {state[6:0], feedback}

    Zero-state recovery uses the corresponding seed.
    """
    state = _check_u8(state)
    feedback = (
        ((state >> 7) & 1)
        ^ ((state >> 5) & 1)
        ^ ((state >> 4) & 1)
        ^ ((state >> 3) & 1)
    )
    nxt = ((state << 1) & 0xFE) | feedback
    return zero_seed if nxt == 0 else nxt


def error_lfsr_next(state: int) -> int:
    return lfsr_next(state, ERROR_LFSR_SEED)


def noise_lfsr_next(state: int) -> int:
    return lfsr_next(state, NOISE_LFSR_SEED)


def hamming_encode(data: int) -> int:
    """
    Hamming SECDED (8,4) encoder.

    Codeword mapping:
      [7] = p0
      [6] = d3
      [5] = d2
      [4] = d1
      [3] = p3
      [2] = d0
      [1] = p2
      [0] = p1
    """
    data = _check_data4(data)
    d0 = (data >> 0) & 1
    d1 = (data >> 1) & 1
    d2 = (data >> 2) & 1
    d3 = (data >> 3) & 1

    p1 = d0 ^ d1 ^ d3
    p2 = d0 ^ d2 ^ d3
    p3 = d1 ^ d2 ^ d3
    p0 = p1 ^ p2 ^ d0 ^ p3 ^ d1 ^ d2 ^ d3

    return (
        (p0 << 7)
        | (d3 << 6)
        | (d2 << 5)
        | (d1 << 4)
        | (p3 << 3)
        | (d0 << 2)
        | (p2 << 1)
        | p1
    )


def inject_bit_error(
    codeword: int, error_state: int, err_mode: int
) -> Tuple[int, int, Tuple[int, ...]]:
    """
    Apply deterministic bit errors using the CURRENT LFSR state.

    The error LFSR is updated exactly once per valid codeword.

    Returns:
        corrupted_codeword, next_error_state, flipped_positions
    """
    codeword = _check_u8(codeword)
    error_state = _check_u8(error_state)
    err_mode = _check_err_mode(err_mode)

    corrupted = codeword
    positions: List[int] = []

    if err_mode == ERR_MODE_SINGLE:
        pos = error_state & 0x7
        corrupted ^= 1 << pos
        positions.append(pos)

    elif err_mode == ERR_MODE_DOUBLE:
        pos1 = error_state & 0x7
        pos2 = (error_state >> 3) & 0x7

        if pos1 == pos2:
            pos2 = (pos2 + 1) % 8

        corrupted ^= 1 << pos1
        corrupted ^= 1 << pos2
        positions.extend((pos1, pos2))

    # err_mode 0 and reserved mode 3 intentionally do not flip bits.

    next_state = error_lfsr_next(error_state)
    return corrupted, next_state, tuple(positions)


def bpsk_modulate(codeword: int) -> List[int]:
    """
    MSB-first BPSK.

    codeword bit 7 occupies samples 0..7,
    bit 6 occupies samples 8..15,
    ...
    bit 0 occupies samples 56..63.
    """
    codeword = _check_u8(codeword)
    samples: List[int] = []

    for bit_index in range(7, -1, -1):
        bit = (codeword >> bit_index) & 1
        value = -127 if bit else 127
        samples.extend([value] * SAMPLES_PER_BIT)

    return samples


def add_noise(
    samples: List[int],
    noise_level: int,
    noise_state: int,
) -> Tuple[List[int], int, List[int]]:
    """
    Add deterministic pseudo-random noise.

    Current noise_lfsr MSB:
      0 -> +A
      1 -> -A

    LFSR updates exactly once per valid sample.
    """
    _check_noise_level(noise_level)
    noise_state = _check_u8(noise_state)
    amplitude = NOISE_AMPLITUDE[noise_level]

    noisy: List[int] = []
    noise_values: List[int] = []
    state = noise_state

    for sample in samples:
        sample = signed8(sample)
        noise = amplitude if ((state >> 7) & 1) == 0 else -amplitude
        raw = sample + noise
        noisy.append(saturate_signed8(raw))
        noise_values.append(noise)
        state = noise_lfsr_next(state)

    return noisy, state, noise_values


def bpsk_demodulate(samples: List[int]) -> int:
    """
    Demodulate 64 samples.

    Every 8 samples are summed in a signed 11-bit equivalent accumulator.
    C >= 0 -> bit 0
    C <  0 -> bit 1
    """
    if len(samples) != SAMPLES_PER_CODEWORD:
        raise ValueError(
            f"expected {SAMPLES_PER_CODEWORD} samples, got {len(samples)}"
        )

    codeword = 0

    for group in range(BITS_PER_CODEWORD):
        acc = sum(signed8(x) for x in samples[group * 8 : group * 8 + 8])
        bit = 1 if acc < 0 else 0
        codeword = (codeword << 1) | bit

    return codeword


def hamming_decode(codeword: int) -> Tuple[int, int, int, int]:
    """
    SECDED decoder.

    Returns:
        data, status, syndrome, corrected_word

    Decision:
      S=000, P=0 -> no error
      S!=000, P=1 -> single-bit correction
      S=000, P=1 -> overall parity-bit error
      S!=000, P=0 -> double-bit detected; data=0 diagnostic value
    """
    codeword = _check_u8(codeword)

    p1 = (codeword >> 0) & 1
    p2 = (codeword >> 1) & 1
    d0 = (codeword >> 2) & 1
    p3 = (codeword >> 3) & 1
    d1 = (codeword >> 4) & 1
    d2 = (codeword >> 5) & 1
    d3 = (codeword >> 6) & 1
    p0 = (codeword >> 7) & 1

    s1 = p1 ^ d0 ^ d1 ^ d3
    s2 = p2 ^ d0 ^ d2 ^ d3
    s3 = p3 ^ d1 ^ d2 ^ d3
    syndrome = (s3 << 2) | (s2 << 1) | s1

    overall_parity = 0
    for i in range(8):
        overall_parity ^= (codeword >> i) & 1

    corrected = codeword
    status = NO_ERROR

    if syndrome == 0 and overall_parity == 0:
        pass

    elif syndrome != 0 and overall_parity == 1:
        # Syndrome is 1..7 and directly maps to codeword bit 0..6.
        corrected ^= 1 << (syndrome - 1)
        status = SINGLE_BIT_CORRECTED

    elif syndrome == 0 and overall_parity == 1:
        # Overall parity bit p0 = codeword[7].
        corrected ^= 1 << 7
        status = SINGLE_BIT_CORRECTED

    else:
        # syndrome != 0 and overall parity == 0
        return 0, DOUBLE_BIT_DETECTED, syndrome, codeword

    data = (
        (((corrected >> 6) & 1) << 3)
        | (((corrected >> 5) & 1) << 2)
        | (((corrected >> 4) & 1) << 1)
        | ((corrected >> 2) & 1)
    )
    return data, status, syndrome, corrected


@dataclass
class TransactionResult:
    input_data: int
    encoded_word: int
    corrupted_word: int
    flipped_positions: Tuple[int, ...]
    bpsk_samples: List[int]
    noise_values: List[int]
    noisy_samples: List[int]
    received_word: int
    result_data: int
    status: int
    syndrome: int
    corrected_word: int
    error_lfsr_before: int
    error_lfsr_after: int
    noise_lfsr_before: int
    noise_lfsr_after: int


class GoldenModel:
    """
    Stateful reference model.

    LFSRs are NOT reseeded between transactions.
    """

    def __init__(
        self,
        error_lfsr: int = ERROR_LFSR_SEED,
        noise_lfsr: int = NOISE_LFSR_SEED,
    ):
        self.error_lfsr = _check_u8(error_lfsr)
        self.noise_lfsr = _check_u8(noise_lfsr)

    def reset(self) -> None:
        self.error_lfsr = ERROR_LFSR_SEED
        self.noise_lfsr = NOISE_LFSR_SEED

    def process(
        self,
        data: int,
        noise_level: int = 0,
        err_mode: int = ERR_MODE_NO_ERROR,
    ) -> TransactionResult:
        data = _check_data4(data)
        _check_noise_level(noise_level)
        _check_err_mode(err_mode)

        error_before = self.error_lfsr
        noise_before = self.noise_lfsr

        encoded = hamming_encode(data)

        corrupted, error_after, positions = inject_bit_error(
            encoded, self.error_lfsr, err_mode
        )

        bpsk = bpsk_modulate(corrupted)

        noisy, noise_after, noise_values = add_noise(
            bpsk, noise_level, self.noise_lfsr
        )

        received = bpsk_demodulate(noisy)

        result, status, syndrome, corrected = hamming_decode(received)

        self.error_lfsr = error_after
        self.noise_lfsr = noise_after

        return TransactionResult(
            input_data=data,
            encoded_word=encoded,
            corrupted_word=corrupted,
            flipped_positions=positions,
            bpsk_samples=bpsk,
            noise_values=noise_values,
            noisy_samples=noisy,
            received_word=received,
            result_data=result,
            status=status,
            syndrome=syndrome,
            corrected_word=corrected,
            error_lfsr_before=error_before,
            error_lfsr_after=error_after,
            noise_lfsr_before=noise_before,
            noise_lfsr_after=noise_after,
        )


def run_transaction(
    data: int,
    noise_level: int = 0,
    err_mode: int = ERR_MODE_NO_ERROR,
) -> TransactionResult:
    """Convenience API: starts from the frozen reset LFSR states."""
    return GoldenModel().process(data, noise_level, err_mode)


def format_result(r: TransactionResult) -> str:
    return (
        f"input={r.input_data:X} "
        f"encoded=0x{r.encoded_word:02X} "
        f"corrupted=0x{r.corrupted_word:02X} "
        f"received=0x{r.received_word:02X} "
        f"result={r.result_data:X} "
        f"status={r.status} "
        f"syndrome={r.syndrome} "
        f"flips={r.flipped_positions}"
    )


if __name__ == "__main__":
    model = GoldenModel()

    for mode in (ERR_MODE_NO_ERROR, ERR_MODE_SINGLE, ERR_MODE_DOUBLE):
        r = model.process(data=0xA, noise_level=0, err_mode=mode)
        print(format_result(r))
