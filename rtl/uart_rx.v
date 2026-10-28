`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 10/28/2026
// Design Name:
// Module Name: uart_rx
// Project Name: FPGA SECDED + BPSK Communication Pipeline
// Target Devices:
// Tool Versions:
// Description:
// UART receiver, 115200 baud, 8-N-1, LSB-first.
// System clock: 50 MHz.
// CLKS_PER_BIT = 434.
// Start bit is checked near its center after 217 clocks.
// Data bits are sampled every 434 clocks.
// o_valid is asserted for one clock after a valid stop bit.
//////////////////////////////////////////////////////////////////////////////////

`default_nettype none

module uart_rx (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_rx,

    output reg  [7:0] o_data,
    output reg        o_valid
);

    // UART timing:
    // System clock = 50 MHz
    // Baud rate = 115200
    // CLKS_PER_BIT = 50_000_000 / 115200 = 434
    localparam integer CLKS_PER_BIT  = 434;

    // Half bit period:
    // Used to verify the start bit near its center.
    // 434 / 2 = 217 clocks.
    localparam integer HALF_BIT_CLKS = 217;

    // UART RX FSM states
    localparam [2:0] IDLE  = 3'd0;
    localparam [2:0] START = 3'd1;
    localparam [2:0] DATA  = 3'd2;
    localparam [2:0] STOP  = 3'd3;

    // Current FSM state
    reg [2:0] r_state;

    // Clock counter inside one UART bit period.
    // 9 bits are sufficient because maximum count is 433.
    reg [8:0] r_clk_count;

    // Current UART data bit index:
    // 0 -> D0
    // 1 -> D1
    // ...
    // 7 -> D7
    reg [2:0] r_bit_index;

    // Internal receive shift/storage register.
    // UART sends data LSB-first.
    reg [7:0] r_data;

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            // Synchronous active-low reset
            r_state     <= IDLE;
            r_clk_count <= 9'd0;
            r_bit_index <= 3'd0;
            r_data      <= 8'd0;
            o_data      <= 8'd0;
            o_valid     <= 1'b0;
        end
        else begin
            // o_valid is a one-clock pulse.
            // It is asserted only after a valid stop bit.
            o_valid <= 1'b0;

            case (r_state)

                IDLE: begin
                    // Reset counters while waiting for a new UART frame.
                    r_clk_count <= 9'd0;
                    r_bit_index <= 3'd0;

                    // UART line is normally HIGH when idle.
                    // A LOW level indicates a possible start bit.
                    if (!i_rx) begin
                        r_state <= START;
                    end
                end

                START: begin
                    // Wait approximately half a bit period.
                    // This moves the sampling point near the center
                    // of the start bit to reject short glitches.
                    if (r_clk_count == HALF_BIT_CLKS - 1) begin
                        r_clk_count <= 9'd0;

                        // The line must still be LOW at the center
                        // of the start bit.
                        if (!i_rx) begin
                            // Valid start bit confirmed.
                            // Begin receiving UART data bits.
                            r_state <= DATA;
                        end
                        else begin
                            // False start bit or noise pulse.
                            // Return to idle and wait for a new frame.
                            r_state <= IDLE;
                        end
                    end
                    else begin
                        r_clk_count <= r_clk_count + 1'b1;
                    end
                end

                DATA: begin
                    // After the center of the start bit has been found,
                    // sample each data bit once every 434 clocks.
                    //
                    // UART format is LSB-first:
                    // D0 -> D1 -> D2 -> ... -> D7.
                    if (r_clk_count == CLKS_PER_BIT - 1) begin
                        r_clk_count <= 9'd0;

                        // Store current serial bit into its correct
                        // position in the received byte.
                        r_data[r_bit_index] <= i_rx;

                        if (r_bit_index == 3'd7) begin
                            // All 8 data bits have been received.
                            // Move to stop-bit checking.
                            r_bit_index <= 3'd0;
                            r_state <= STOP;
                        end
                        else begin
                            // Continue with the next data bit.
                            r_bit_index <= r_bit_index + 1'b1;
                        end
                    end
                    else begin
                        r_clk_count <= r_clk_count + 1'b1;
                    end
                end

                STOP: begin
                    // Wait one full bit period from the last data sample
                    // and sample the stop bit.
                    //
                    // For UART 8-N-1, the stop bit must be HIGH.
                    if (r_clk_count == CLKS_PER_BIT - 1) begin
                        r_clk_count <= 9'd0;

                        if (i_rx) begin
                            // Valid stop bit.
                            // Publish the received byte and assert
                            // o_valid for exactly one clock.
                            o_data  <= r_data;
                            o_valid <= 1'b1;
                        end

                        // Whether stop bit is valid or invalid,
                        // return to IDLE and wait for the next frame.
                        r_state <= IDLE;
                    end
                    else begin
                        r_clk_count <= r_clk_count + 1'b1;
                    end
                end

                default: begin
                    // Safety recovery for illegal FSM state.
                    r_state     <= IDLE;
                    r_clk_count <= 9'd0;
                    r_bit_index <= 3'd0;
                end

            endcase
        end
    end

endmodule

`default_nettype wire