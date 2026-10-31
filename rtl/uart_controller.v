`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
// Create Date: 10/28/2026
// Design Name:
// Module Name: uart_controller
// Project Name: FPGA SECDED + BPSK Communication Pipeline
// Target Devices:
// Tool Versions:
// Description:
// UART protocol controller for the SECDED + BPSK DSP pipeline.
// Receives CONFIG and DATA bytes from uart_rx.
// Processes data_hi first, then data_lo through tx_rx_dsp_top.
// Sends two UART response bytes:
// response_byte0 = {result_hi, result_lo}
// response_byte1 = {4'b0000, status_hi, status_lo}
//////////////////////////////////////////////////////////////////////////////////

`default_nettype none

module uart_controller (
    input  wire       i_clk,
    input  wire       i_rst_n,

    input  wire [7:0] i_rx_data,
    input  wire       i_rx_valid,

    input  wire [3:0] i_dsp_result,
    input  wire [1:0] i_dsp_status,
    input  wire       i_dsp_done,

    input  wire       i_tx_busy,

    output reg  [3:0] o_dsp_data,
    output reg  [2:0] o_noise_level,
    output reg  [1:0] o_err_mode,
    output reg        o_dsp_start,

    output reg  [7:0] o_tx_data,
    output reg        o_tx_start
);

    // Controller FSM states
    localparam [3:0] WAIT_CONFIG       = 4'd0;
    localparam [3:0] WAIT_DATA         = 4'd1;
    localparam [3:0] START_HIGH        = 4'd2;
    localparam [3:0] WAIT_HIGH_DONE    = 4'd3;
    localparam [3:0] START_LOW         = 4'd4;
    localparam [3:0] WAIT_LOW_DONE     = 4'd5;
    localparam [3:0] SEND_RESULT       = 4'd6;
    localparam [3:0] WAIT_RESULT_BUSY  = 4'd7;
    localparam [3:0] WAIT_RESULT_DONE  = 4'd8;
    localparam [3:0] SEND_STATUS       = 4'd9;
    localparam [3:0] WAIT_STATUS_BUSY  = 4'd10;
    localparam [3:0] WAIT_STATUS_DONE  = 4'd11;

    // Current FSM state
    reg [3:0] r_state;

    // DATA byte storage:
    // [7:4] = data_hi
    // [3:0] = data_lo
    reg [7:0] r_data_byte;

    // Store DSP results for both nibble transactions
    reg [3:0] r_result_hi;
    reg [3:0] r_result_lo;
    reg [1:0] r_status_hi;
    reg [1:0] r_status_lo;

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            // Synchronous active-low reset
            r_state         <= WAIT_CONFIG;
            r_data_byte     <= 8'd0;
            r_result_hi     <= 4'd0;
            r_result_lo     <= 4'd0;
            r_status_hi     <= 2'b00;
            r_status_lo     <= 2'b00;

            o_dsp_data      <= 4'd0;
            o_noise_level   <= 3'd0;
            o_err_mode      <= 2'b00;
            o_dsp_start     <= 1'b0;

            o_tx_data       <= 8'd0;
            o_tx_start      <= 1'b0;
        end
        else begin
            // Start signals are one-clock pulses
            o_dsp_start <= 1'b0;
            o_tx_start  <= 1'b0;

            case (r_state)

                WAIT_CONFIG: begin
                    // CONFIG byte format:
                    // [7:5] = 000
                    // [4:2] = noise_level
                    // [1:0] = err_mode
                    if (i_rx_valid) begin
                        o_noise_level <= i_rx_data[4:2];
                        o_err_mode    <= i_rx_data[1:0];
                        r_state       <= WAIT_DATA;
                    end
                end

                WAIT_DATA: begin
                    // DATA byte format:
                    // [7:4] = data_hi
                    // [3:0] = data_lo
                    if (i_rx_valid) begin
                        r_data_byte <= i_rx_data;
                        r_state     <= START_HIGH;
                    end
                end

                START_HIGH: begin
                    // Process high nibble first
                    o_dsp_data  <= r_data_byte[7:4];
                    o_dsp_start <= 1'b1;
                    r_state     <= WAIT_HIGH_DONE;
                end

                WAIT_HIGH_DONE: begin
                    // Wait for first DSP transaction to complete
                    if (i_dsp_done) begin
                        r_result_hi <= i_dsp_result;
                        r_status_hi <= i_dsp_status;
                        r_state     <= START_LOW;
                    end
                end

                START_LOW: begin
                    // Process low nibble second
                    o_dsp_data  <= r_data_byte[3:0];
                    o_dsp_start <= 1'b1;
                    r_state     <= WAIT_LOW_DONE;
                end

                WAIT_LOW_DONE: begin
                    // Wait for second DSP transaction to complete
                    if (i_dsp_done) begin
                        r_result_lo <= i_dsp_result;
                        r_status_lo <= i_dsp_status;
                        r_state     <= SEND_RESULT;
                    end
                end

                SEND_RESULT: begin
                    // First response byte:
                    // {result_hi[3:0], result_lo[3:0]}
                    //
                    // Start TX only when transmitter is idle.
                    if (!i_tx_busy) begin
                        o_tx_data  <= {r_result_hi, r_result_lo};
                        o_tx_start <= 1'b1;
                        r_state    <= WAIT_RESULT_BUSY;
                    end
                end

                WAIT_RESULT_BUSY: begin
                    // Wait until uart_tx accepts the request
                    // and raises o_busy.
                    if (i_tx_busy) begin
                        r_state <= WAIT_RESULT_DONE;
                    end
                end

                WAIT_RESULT_DONE: begin
                    // Wait until first response byte is fully transmitted.
                    if (!i_tx_busy) begin
                        r_state <= SEND_STATUS;
                    end
                end

                SEND_STATUS: begin
                    // Second response byte:
                    // {4'b0000, status_hi[1:0], status_lo[1:0]}
                    //
                    // Start TX only when transmitter is idle.
                    if (!i_tx_busy) begin
                        o_tx_data  <= {
                            4'b0000,
                            r_status_hi,
                            r_status_lo
                        };
                        o_tx_start <= 1'b1;
                        r_state    <= WAIT_STATUS_BUSY;
                    end
                end

                WAIT_STATUS_BUSY: begin
                    // Wait until uart_tx accepts the second byte.
                    if (i_tx_busy) begin
                        r_state <= WAIT_STATUS_DONE;
                    end
                end

                WAIT_STATUS_DONE: begin
                    // Complete current request only after the second
                    // response byte has finished transmitting.
                    if (!i_tx_busy) begin
                        r_state <= WAIT_CONFIG;
                    end
                end

                default: begin
                    // Safety recovery for illegal FSM state.
                    r_state <= WAIT_CONFIG;
                end

            endcase
        end
    end

endmodule

`default_nettype wire