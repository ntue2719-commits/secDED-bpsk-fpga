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
    error_lfsr_next,
    noise_lfsr_next,
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


def test_noise_uses_current_lfsr_state():
    """Noise polarity uses the pre-update LFSR state, even at level 0."""
    for seed in (0x01, 0x80, 0xA5):
        for level, amplitude in enumerate(NOISE_AMPLITUDE):
            state = seed
            samples = [127, -127, 127, -127, 127]
            noisy, state_after, noise_values = add_noise(samples, level, seed)
            for sample, actual_noise, actual_sample in zip(samples, noise_values, noisy):
                expected_noise = -amplitude if state & 0x80 else amplitude
                assert actual_noise == expected_noise
                assert actual_sample == max(-128, min(127, sample + expected_noise))
                state = noise_lfsr_next(state)
            assert state_after == state


def test_noise_sign_preservation_exhaustive():
    """Frozen amplitudes cannot invert a BPSK symbol or demodulated bit."""
    for level in range(8):
        for codeword in range(256):
            tx = bpsk_modulate(codeword)
            noisy, _, _ = add_noise(tx, level, NOISE_LFSR_SEED)
            assert all((a > 0) == (b > 0) for a, b in zip(tx, noisy))
            assert bpsk_demodulate(noisy) == codeword


def test_error_lfsr_current_state_and_reserved_mode():
    """Current state selects positions; every accepted codeword advances state."""
    for seed in (0xA5, 0x00, 0xFF):
        for mode in (ERR_MODE_NO_ERROR, ERR_MODE_SINGLE,
                     ERR_MODE_DOUBLE, ERR_MODE_RESERVED):
            corrupted, next_state, positions = inject_bit_error(0x5A, seed, mode)
            assert next_state == error_lfsr_next(seed)
            if mode in (ERR_MODE_NO_ERROR, ERR_MODE_RESERVED):
                assert corrupted == 0x5A and positions == ()
            elif mode == ERR_MODE_SINGLE:
                assert positions == (seed & 7,)
                assert corrupted == (0x5A ^ (1 << positions[0]))
            else:
                p1, p2 = seed & 7, (seed >> 3) & 7
                if p1 == p2:
                    p2 = (p2 + 1) % 8
                assert positions == (p1, p2)
                assert corrupted == (0x5A ^ (1 << p1) ^ (1 << p2))


def test_full_dsp_matrix():
    """384 transactions, one model instance, continuous non-reseeded LFSRs."""
    model = GoldenModel()
    count = 0
    for data in range(16):
        for noise_level in range(8):
            for err_mode in (ERR_MODE_NO_ERROR, ERR_MODE_SINGLE, ERR_MODE_DOUBLE):
                before_error = model.error_lfsr
                before_noise = model.noise_lfsr
                r = model.process(data, noise_level, err_mode)
                assert r.input_data == data
                assert r.encoded_word == hamming_encode(data)
                assert r.error_lfsr_before == before_error
                assert r.noise_lfsr_before == before_noise
                assert r.error_lfsr_after == error_lfsr_next(before_error)
                expected_noise_state = before_noise
                for _ in range(64):
                    expected_noise_state = noise_lfsr_next(expected_noise_state)
                assert r.noise_lfsr_after == expected_noise_state
                assert model.error_lfsr == r.error_lfsr_after
                assert model.noise_lfsr == r.noise_lfsr_after
                assert len(r.bpsk_samples) == len(r.noisy_samples) == 64
                assert r.bpsk_samples == bpsk_modulate(r.corrupted_word)
                assert r.received_word == r.corrupted_word
                expected_data, expected_status, expected_syndrome, expected_cw = (
                    hamming_decode(r.received_word)
                )
                assert (r.result_data, r.status, r.syndrome, r.corrected_word) == (
                    expected_data, expected_status, expected_syndrome, expected_cw
                )
                if err_mode == ERR_MODE_NO_ERROR:
                    assert (r.result_data, r.status) == (data, NO_ERROR)
                elif err_mode == ERR_MODE_SINGLE:
                    assert (r.result_data, r.status) == (data, SINGLE_BIT_CORRECTED)
                else:
                    assert (r.result_data, r.status) == (0, DOUBLE_BIT_DETECTED)
                count += 1
    assert count == 384


def test_reset_restores_determinism():
    model = GoldenModel()
    first = model.process(0xA, noise_level=7, err_mode=ERR_MODE_DOUBLE)
    model.process(0x1, noise_level=3, err_mode=ERR_MODE_SINGLE)
    model.reset()
    replay = model.process(0xA, noise_level=7, err_mode=ERR_MODE_DOUBLE)
    assert replay == first


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
    test_noise_uses_current_lfsr_state()
    test_noise_sign_preservation_exhaustive()
    test_error_lfsr_current_state_and_reserved_mode()
    test_full_dsp_matrix()
    test_reset_restores_determinism()
    print("PASS: all golden-model tests")
