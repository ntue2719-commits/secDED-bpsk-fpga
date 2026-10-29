`timescale 1ns / 1ps
`default_nettype none

// ============================================================
// Module      : tx_rx_dsp_top
// Description : SECDED + BPSK DSP Pipeline Top-Level
// Clock       : 50 MHz
// Reset       : Active-low
//
// Pipeline:
//   Hamming Encoder
//     -> Bit Flip Channel
//     -> BPSK Modulator
//     -> LFSR Noise Injector
//     -> BPSK Demodulator
//     -> Hamming Decoder
// ============================================================

module tx_rx_dsp_top (
    // --------------------------------------------------------
    // Clock and Reset
    // --------------------------------------------------------
    input  wire               i_clk,
    input  wire               i_rst_n,

    // --------------------------------------------------------
    // Transaction Interface
    // --------------------------------------------------------
    input  wire [3:0]         i_data,
    input  wire [2:0]         i_noise_level,
    input  wire [1:0]         i_err_mode,
    input  wire               i_start,

    // --------------------------------------------------------
    // Result Interface
    // --------------------------------------------------------
    output reg  [3:0]         o_data,
    output reg  [1:0]         o_status,
    output reg                o_done
);

    // ========================================================
    // 1. Hamming Encoder -> Bit Flip Channel
    // ========================================================
    wire [7:0]               w_encoded_word;
    wire                     w_encoded_valid;

    // ========================================================
    // 2. Bit Flip Channel -> BPSK Modulator
    // ========================================================
    wire [7:0]               w_corrupted_word;
    wire                     w_corrupted_valid;

    // ========================================================
    // 3. BPSK Modulator -> LFSR Noise Injector
    // ========================================================
    wire signed [7:0]        w_bpsk_sample;
    wire                     w_bpsk_valid;
    wire                     w_bpsk_done;

    // ========================================================
    // 4. LFSR Noise Injector -> BPSK Demodulator
    // ========================================================
    wire signed [7:0]        w_noisy_sample;
    wire                     w_noisy_valid;
    wire                     w_noisy_done;

    // ========================================================
    // 5. BPSK Demodulator -> Hamming Decoder
    // ========================================================
    wire [7:0]               w_demod_word;
    wire                     w_demod_valid;

    // ========================================================
    // 6. Hamming Decoder -> Result Interface
    // ========================================================
    wire [3:0]               w_decoded_data;
    wire [1:0]               w_decoded_status;
    wire                     w_decoded_valid;

    // ========================================================
    // Transaction Control & Configuration Latching
    // ========================================================
    reg [2:0] r_noise_level;
    reg [1:0] r_err_mode;
    reg       r_busy;

    wire w_start_gated = i_start && !r_busy;

    // ========================================================
    // Sub-Module Instantiations
    // ========================================================
    // Stage 1: (8,4) SECDED encoding (4-bit payload -> 8-bit codeword)
    hamming_encoder u_hamming_encoder (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_data     (i_data),
        .i_start    (w_start_gated),
        .o_codeword (w_encoded_word),
        .o_valid    (w_encoded_valid)
    );
    // Stage 2: Inject 0, 1, or 2 bit errors based on latched r_err_mode
    bit_flip_channel u_bit_flip_channel (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_codeword (w_encoded_word),
        .i_valid    (w_encoded_valid),
        .i_err_mode (r_err_mode),
        .o_codeword (w_corrupted_word),
        .o_valid    (w_corrupted_valid)
    );
    // Stage 3: BPSK modulation (8 samples/bit -> 64 signed samples total)
    bpsk_modulator u_bpsk_modulator (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_codeword (w_corrupted_word),
        .i_valid    (w_corrupted_valid),
        .o_sample   (w_bpsk_sample),
        .o_valid    (w_bpsk_valid),
        .o_done     (w_bpsk_done)
    );
    // Stage 4: Signed additive LFSR noise injection with [-128, 127] saturation
    lfsr_noise_injector u_lfsr_noise_injector (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_sample      (w_bpsk_sample),
        .i_valid       (w_bpsk_valid),
        .i_done        (w_bpsk_done),
        .i_noise_level (r_noise_level),
        .o_sample      (w_noisy_sample),
        .o_valid       (w_noisy_valid),
        .o_done        (w_noisy_done)
    );
    // Stage 5: BPSK correlation demodulator (accumulates 8 samples/bit)
    bpsk_demodulator u_bpsk_demodulator (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_sample   (w_noisy_sample),
        .i_valid    (w_noisy_valid),
        .i_done     (w_noisy_done),
        .o_codeword (w_demod_word),
        .o_valid    (w_demod_valid)
    );
    // Stage 6: SECDED decoder (corrects 1 bit, detects 2 bits)
    hamming_decoder u_hamming_decoder (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_codeword (w_demod_word),
        .i_valid    (w_demod_valid),
        .o_data     (w_decoded_data),
        .o_status   (w_decoded_status),
        .o_valid    (w_decoded_valid)
    );

    // ========================================================
    // Output Registration & Completion Handshake
    // ========================================================
    always @ (posedge i_clk) begin
        if (!i_rst_n) begin
            r_noise_level <= 3'd0;
            r_err_mode    <= 2'd0;
            r_busy        <= 1'b0;
            o_data        <= 4'd0;
            o_status      <= 2'd0;
            o_done        <= 1'b0;
        end
        else begin
            // Default 1-clock completion pulse
            o_done <= 1'b0;

            if (!r_busy) begin
                // Latch configuration when new transaction starts
                if (i_start) begin
                    r_busy        <= 1'b1;
                    r_noise_level <= i_noise_level;
                    r_err_mode    <= i_err_mode;
                end
            end
            else if (w_decoded_valid) begin
                // Latch decoded results, assert o_done pulse, and release busy flag
                o_data   <= w_decoded_data;
                o_status <= w_decoded_status;
                o_done   <= 1'b1;
                r_busy   <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
