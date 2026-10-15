
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
//
// Status      : Skeleton - signals only
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

endmodule

`default_nettype wire
