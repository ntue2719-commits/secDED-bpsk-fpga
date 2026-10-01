"""Verification tests for the SECDED + BPSK Golden Model."""

from golden_model import (
    GoldenModel,
    ERR_MODE_NO_ERROR,
    ERR_MODE_SINGLE,
    ERR_MODE_DOUBLE,
    ERR_MODE_RESERVED,
    NO_ERROR,
    SINGLE_BIT_CORRECTED,
    DOUBLE_BIT_DETECTED,
    ERROR_LFSR_SEED,
    NOISE_LFSR_SEED,
    NOISE_AMPLITUDE,
    hamming_encode,
    hamming_decode,
    inject_bit_error,
    bpsk_modulate,
    bpsk_demodulate,
    add_noise,
)


def test_hamming_encoder_exhaustive():
    # Basic structural checks for all 16 input values.
    assert len({hamming_encode(d) for d in range(16)}) == 16

    for d in range(16):
        cw = hamming_encode(d)
        decoded, status, syndrome, corrected = hamming_decode(cw)
        assert decoded == d
        assert status == NO_ERROR
        assert syndrome == 0
        assert corrected == cw


def test_hamming_single_bit_exhaustive():
    for d in range(16):
        cw = hamming_encode(d)

        for pos in range(8):
            corrupted = cw ^ (1 << pos)
            decoded, status, syndrome, corrected = hamming_decode(corrupted)

            assert decoded == d
            assert status == SINGLE_BIT_CORRECTED
            assert syndrome != 0 or pos == 7
            assert corrected == cw


def test_hamming_double_bit():
    checked = 0

    for d in range(16):
        cw = hamming_encode(d)

        for p1 in range(8):
            for p2 in range(p1 + 1, 8):
                corrupted = cw ^ (1 << p1) ^ (1 << p2)
                decoded, status, syndrome, corrected = hamming_decode(corrupted)

                assert status == DOUBLE_BIT_DETECTED
                assert decoded == 0
                assert syndrome != 0
                assert corrected == corrupted
                checked += 1

    assert checked == 16 * 28


def test_bpsk_all_codewords():
    for cw in range(256):
        samples = bpsk_modulate(cw)
        assert len(samples) == 64
        assert bpsk_demodulate(samples) == cw


def test_noise_level_zero():
    samples = bpsk_modulate(0xA5)
    noisy, next_state, noise_values = add_noise(
        samples, 0, NOISE_LFSR_SEED
    )
    assert noisy == samples
    assert all(v == 0 for v in noise_values)
    assert next_state != NOISE_LFSR_SEED


def test_noise_lut():
    for level, amplitude in enumerate(NOISE_AMPLITUDE):
        samples = [127] * 64
        noisy, _, noise_values = add_noise(samples, level, NOISE_LFSR_SEED)

        assert all(abs(v) == amplitude for v in noise_values)
        assert all(-128 <= v <= 127 for v in noisy)

        if amplitude == 0:
            assert noisy == samples


def test_saturation_boundaries():
    # +127 + 64 = +191 -> +127
    noisy, _, _ = add_noise([127], 7, 0x01)
    assert noisy[0] == 127

    # To exercise negative saturation deterministically, use an LFSR
    # state with MSB=1: noise is -64.
    noisy, _, _ = add_noise([-127], 7, 0x80)
    assert noisy[0] == -128


def test_error_lfsr_update_once_per_transaction():
    state = ERROR_LFSR_SEED

    _, next0, _ = inject_bit_error(0, state, ERR_MODE_NO_ERROR)
    _, next1, _ = inject_bit_error(0, next0, ERR_MODE_NO_ERROR)

    assert next0 != state
    assert next1 != next0


def test_error_modes_and_reserved_mode():
    for d in range(16):
        model = GoldenModel()

        r0 = model.process(d, noise_level=0, err_mode=ERR_MODE_NO_ERROR)
        assert r0.result_data == d
        assert r0.status == NO_ERROR

        model = GoldenModel()
        r1 = model.process(d, noise_level=0, err_mode=ERR_MODE_SINGLE)
        assert r1.result_data == d
        assert r1.status == SINGLE_BIT_CORRECTED

        model = GoldenModel()
        r2 = model.process(d, noise_level=0, err_mode=ERR_MODE_DOUBLE)
        assert r2.result_data == 0
        assert r2.status == DOUBLE_BIT_DETECTED

        model = GoldenModel()
        rr = model.process(d, noise_level=0, err_mode=ERR_MODE_RESERVED)
        assert rr.result_data == d
        assert rr.status == NO_ERROR


def test_full_dsp_matrix():
    # Frozen minimum verification matrix:
    # 16 inputs x 8 noise levels x 3 useful error modes = 384 transactions.
    for data in range(16):
        for noise_level in range(8):
            for err_mode in (
                ERR_MODE_NO_ERROR,
                ERR_MODE_SINGLE,
                ERR_MODE_DOUBLE,
            ):
                model = GoldenModel()
                r = model.process(data, noise_level, err_mode)

                assert len(r.bpsk_samples) == 64
                assert len(r.noisy_samples) == 64
                assert r.error_lfsr_before == ERROR_LFSR_SEED
                assert r.noise_lfsr_before == NOISE_LFSR_SEED


if __name__ == "__main__":
    test_hamming_encoder_exhaustive()
    test_hamming_single_bit_exhaustive()
    test_hamming_double_bit()
    test_bpsk_all_codewords()
    test_noise_level_zero()
    test_noise_lut()
    test_saturation_boundaries()
    test_error_lfsr_update_once_per_transaction()
    test_error_modes_and_reserved_mode()
    test_full_dsp_matrix()
    print("PASS: all golden-model tests")
