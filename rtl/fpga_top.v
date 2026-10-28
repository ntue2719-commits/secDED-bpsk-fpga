`timescale 1ns / 1ps
// Company:
// Engineer:
//
// Create Date: 10/28/2026
// Design Name:
// Module Name: fpga_top
// Project Name: FPGA SECDED + BPSK Communication Pipeline
// Target Devices:
// Tool Versions:
// Description:
// Board/system-level wrapper for UART and SECDED + BPSK DSP pipeline.
// Connects uart_rx -> uart_controller -> tx_rx_dsp_top -> uart_controller -> uart_tx.
//////////////////////////////////////////////////////////////////////////////////

`default_nettype none

module fpga_top #(
    parameter integer UART_CLKS_PER_BIT = 434
)(
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_uart_rx,

    output wire o_uart_tx
);

    // UART RX -> Controller
    wire [7:0] w_rx_data;
    wire       w_rx_valid;

    // Controller -> DSP
    wire [3:0] w_dsp_data;
    wire [2:0] w_noise_level;
    wire [1:0] w_err_mode;
    wire       w_dsp_start;

    // DSP -> Controller
    wire [3:0] w_dsp_result;
    wire [1:0] w_dsp_status;
    wire       w_dsp_done;

    // Controller -> UART TX
    wire [7:0] w_tx_data;
    wire       w_tx_start;

    // UART TX -> Controller
    wire       w_tx_busy;

    // UART receiver:
    // Convert serial UART RX data into 8-bit parallel bytes.
    // UART_CLKS_PER_BIT defaults to 434 for 50 MHz / 115200 baud.
    // The parameter can be overridden in simulation
    // to reduce simulation time.
    uart_rx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_rx (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_rx       (i_uart_rx),

        .o_data     (w_rx_data),
        .o_valid    (w_rx_valid)
    );

    // UART protocol controller:
    // Receive CONFIG and DATA bytes,
    // run high nibble then low nibble through DSP,
    // and send two response bytes through uart_tx.
    uart_controller u_uart_controller (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),

        .i_rx_data      (w_rx_data),
        .i_rx_valid     (w_rx_valid),

        .i_dsp_result   (w_dsp_result),
        .i_dsp_status   (w_dsp_status),
        .i_dsp_done     (w_dsp_done),

        .i_tx_busy      (w_tx_busy),

        .o_dsp_data     (w_dsp_data),
        .o_noise_level  (w_noise_level),
        .o_err_mode     (w_err_mode),
        .o_dsp_start    (w_dsp_start),

        .o_tx_data      (w_tx_data),
        .o_tx_start     (w_tx_start)
    );

    // SECDED + BPSK DSP pipeline:
    // Process one 4-bit nibble per transaction.
    tx_rx_dsp_top u_tx_rx_dsp_top (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),

        .i_data         (w_dsp_data),
        .i_noise_level  (w_noise_level),
        .i_err_mode     (w_err_mode),
        .i_start        (w_dsp_start),

        .o_data         (w_dsp_result),
        .o_status       (w_dsp_status),
        .o_done         (w_dsp_done)
    );

    // UART transmitter:
    // Convert controller response bytes into serial UART TX data.
    // UART_CLKS_PER_BIT defaults to 434 for 50 MHz / 115200 baud.
    // The parameter can be overridden in simulation
    // to reduce simulation time.
    uart_tx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_tx (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),

        .i_data     (w_tx_data),
        .i_start    (w_tx_start),

        .o_tx       (o_uart_tx),
        .o_busy     (w_tx_busy)
    );

endmodule

`default_nettype wire