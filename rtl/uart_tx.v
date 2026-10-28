`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
// Create Date: 10/28/2026
// Design Name:
// Module Name: uart_tx
// Project Name: FPGA SECDED + BPSK Communication Pipeline
// Target Devices:
// Tool Versions:
// Description:
// UART transmitter, 115200 baud, 8-N-1, LSB-first.
// System clock: 50 MHz.
// Default CLKS_PER_BIT = 434.
// i_start is accepted only while idle.
// o_busy remains HIGH during the complete UART frame.
//////////////////////////////////////////////////////////////////////////////////

`default_nettype none

module uart_tx #(
    parameter integer CLKS_PER_BIT = 434
)(
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire [7:0] i_data,
    input  wire       i_start,

    output reg        o_tx,
    output reg        o_busy
);

    // UART timing:
    // System clock = 50 MHz
    // Baud rate = 115200
    // Default CLKS_PER_BIT = 50_000_000 / 115200 = 434
    // The parameter can be overridden in simulation
    // to reduce simulation time.

    // UART TX FSM states
    localparam [2:0] IDLE  = 3'd0;
    localparam [2:0] START = 3'd1;
    localparam [2:0] DATA  = 3'd2;
    localparam [2:0] STOP  = 3'd3;

    // Current FSM state
    reg [2:0] r_state;

    // Clock counter inside one UART bit period.
    // 9 bits are sufficient for the default maximum count of 433.
    reg [8:0] r_clk_count;

    // Current UART data bit index:
    // 0 -> D0
    // 1 -> D1
    // ...
    // 7 -> D7
    reg [2:0] r_bit_index;

    // Data register:
    // Input byte is captured when i_start is accepted.
    reg [7:0] r_data;

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            // Synchronous active-low reset
            r_state     <= IDLE;
            r_clk_count <= 9'd0;
            r_bit_index <= 3'd0;
            r_data      <= 8'd0;
            o_tx        <= 1'b1;
            o_busy      <= 1'b0;
        end
        else begin
            case (r_state)

                IDLE: begin
                    // UART TX line is HIGH while idle.
                    o_tx        <= 1'b1;
                    o_busy      <= 1'b0;
                    r_clk_count <= 9'd0;
                    r_bit_index <= 3'd0;

                    // Accept a new byte only while transmitter is idle.
                    if (i_start) begin
                        // Capture the complete input byte before transmission.
                        r_data <= i_data;

                        // Start transmission immediately with the start bit.
                        o_tx   <= 1'b0;
                        o_busy <= 1'b1;
                        r_state <= START;
                    end
                end

                START: begin
                    // Start bit must remain LOW for one complete bit period.
                    o_tx   <= 1'b0;
                    o_busy <= 1'b1;

                    if (r_clk_count == CLKS_PER_BIT - 1) begin
                        r_clk_count <= 9'd0;

                        // UART sends data LSB-first.
                        // Begin with data bit D0.
                        o_tx <= r_data[0];
                        r_bit_index <= 3'd0;
                        r_state <= DATA;
                    end
                    else begin
                        r_clk_count <= r_clk_count + 1'b1;
                    end
                end

                DATA: begin
                    // Keep the currently selected data bit stable
                    // for one complete UART bit period.
                    o_tx   <= r_data[r_bit_index];
                    o_busy <= 1'b1;

                    if (r_clk_count == CLKS_PER_BIT - 1) begin
                        r_clk_count <= 9'd0;

                        if (r_bit_index == 3'd7) begin
                            // All 8 data bits have been transmitted.
                            // Drive HIGH for the stop bit.
                            o_tx <= 1'b1;
                            r_bit_index <= 3'd0;
                            r_state <= STOP;
                        end
                        else begin
                            // Move to the next UART data bit.
                            r_bit_index <= r_bit_index + 1'b1;
                        end
                    end
                    else begin
                        r_clk_count <= r_clk_count + 1'b1;
                    end
                end

                STOP: begin
                    // UART 8-N-1 requires one HIGH stop bit.
                    o_tx   <= 1'b1;
                    o_busy <= 1'b1;

                    if (r_clk_count == CLKS_PER_BIT - 1) begin
                        r_clk_count <= 9'd0;

                        // Complete current frame and return to idle.
                        o_busy  <= 1'b0;
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
                    o_tx        <= 1'b1;
                    o_busy      <= 1'b0;
                end

            endcase
        end
    end

endmodule

`default_nettype wire