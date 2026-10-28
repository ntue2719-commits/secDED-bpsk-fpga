`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 10/28/2026
// Design Name:
// Module Name: tb_fpga_top
// Project Name: FPGA SECDED + BPSK Communication Pipeline
// Target Devices:
// Tool Versions:
// Description:
// Final black-box end-to-end testbench.
// Sends UART CONFIG + DATA bytes into fpga_top,
// receives two UART response bytes,
// and compares them against Python Golden Model vectors.
//////////////////////////////////////////////////////////////////////////////////

`default_nettype none

module tb_fpga_top;

    localparam integer CLK_PERIOD    = 20;

    // Fast UART timing for simulation.
    // Hardware default remains 434 clocks/bit.
    localparam integer CLKS_PER_BIT  = 8;
    localparam integer HALF_BIT_CLKS = CLKS_PER_BIT / 2;

    localparam integer NUM_REQUESTS  = 96;

    // Absolute path to the project data directory.
    // Use forward slashes for Vivado/XSim on Windows.
    localparam string DATA_DIR =
        "D:/FPGA_Project/secDED/secDED-bpsk-fpga/data";

    reg i_clk;
    reg i_rst_n;
    reg i_uart_rx;

    wire o_uart_tx;

    reg [7:0] config_mem          [0:NUM_REQUESTS-1];
    reg [7:0] data_mem            [0:NUM_REQUESTS-1];
    reg [7:0] expected_data_mem   [0:NUM_REQUESTS-1];
    reg [7:0] expected_status_mem [0:NUM_REQUESTS-1];

    integer request_index;
    integer checks;
    integer errors;

    reg [7:0] rx_byte0;
    reg [7:0] rx_byte1;

    fpga_top #(
        .UART_CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut (
        .i_clk     (i_clk),
        .i_rst_n   (i_rst_n),
        .i_uart_rx (i_uart_rx),
        .o_uart_tx (o_uart_tx)
    );

    // 50 MHz system clock
    initial begin
        i_clk = 1'b0;
        forever #(CLK_PERIOD/2) i_clk = ~i_clk;
    end

    // Send one complete UART 8-N-1 frame to DUT.
    // UART data is transmitted LSB-first.
    task automatic uart_send_byte;
        input [7:0] tx_byte;
        integer bit_index;
        begin
            // Drive UART stimulus on the falling edge of the system clock.
            // DUT samples on rising edges, so this avoids testbench/DUT races.

            // Start bit
            @(negedge i_clk);
            i_uart_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(negedge i_clk);

            // D0 ... D7
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                i_uart_rx = tx_byte[bit_index];
                repeat (CLKS_PER_BIT) @(negedge i_clk);
            end

            // Stop bit
            i_uart_rx = 1'b1;
            repeat (CLKS_PER_BIT) @(negedge i_clk);
        end
    endtask

    // Receive one complete UART 8-N-1 frame from DUT.
    // Sampling is performed near the center of each UART bit.
    task automatic uart_receive_byte;
        output [7:0] rx_byte;
        integer bit_index;
        begin
            rx_byte = 8'h00;

            // Wait for falling edge of start bit.
            @(negedge o_uart_tx);

            // Move to the center of the start bit.
            repeat (HALF_BIT_CLKS) @(posedge i_clk);

            checks = checks + 1;
            if (o_uart_tx !== 1'b0) begin
                errors = errors + 1;
                $display(
                    "ERROR: Invalid UART TX start bit at time %0t",
                    $time
                );
            end

            // Move one complete bit period to center of D0,
            // then sample D0 ... D7.
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (CLKS_PER_BIT) @(posedge i_clk);
                rx_byte[bit_index] = o_uart_tx;
            end

            // Move to center of stop bit and verify HIGH.
            repeat (CLKS_PER_BIT) @(posedge i_clk);

            checks = checks + 1;
            if (o_uart_tx !== 1'b1) begin
                errors = errors + 1;
                $display(
                    "ERROR: Invalid UART TX stop bit at time %0t",
                    $time
                );
            end
        end
    endtask

    // Compare one UART request against expected Golden Model response.
    task automatic check_request;
        input integer index;
        begin
            // Host -> FPGA:
            // Byte 0 = CONFIG
            // Byte 1 = DATA
            uart_send_byte(config_mem[index]);
            uart_send_byte(data_mem[index]);

            // FPGA -> Host:
            // Byte 0 = {result_hi, result_lo}
            // Byte 1 = {4'b0000, status_hi, status_lo}
            uart_receive_byte(rx_byte0);
            uart_receive_byte(rx_byte1);

            checks = checks + 1;
            if (rx_byte0 !== expected_data_mem[index]) begin
                errors = errors + 1;
                $display(
                    "ERROR request %0d DATA: config=%02h input=%02h expected=%02h got=%02h",
                    index,
                    config_mem[index],
                    data_mem[index],
                    expected_data_mem[index],
                    rx_byte0
                );
            end

            checks = checks + 1;
            if (rx_byte1 !== expected_status_mem[index]) begin
                errors = errors + 1;
                $display(
                    "ERROR request %0d STATUS: config=%02h input=%02h expected=%02h got=%02h",
                    index,
                    config_mem[index],
                    data_mem[index],
                    expected_status_mem[index],
                    rx_byte1
                );
            end
        end
    endtask

    initial begin
        i_rst_n   = 1'b0;
        i_uart_rx = 1'b1;

        checks    = 0;
        errors    = 0;

        rx_byte0  = 8'h00;
        rx_byte1  = 8'h00;

        // UART-level vectors generated from Python Golden Model.
        $readmemh(
            {DATA_DIR, "/uart_config.hex"},
            config_mem
        );

        $readmemh(
            {DATA_DIR, "/uart_data.hex"},
            data_mem
        );

        $readmemh(
            {DATA_DIR, "/uart_expected_data.hex"},
            expected_data_mem
        );

        $readmemh(
            {DATA_DIR, "/uart_expected_status.hex"},
            expected_status_mem
        );

        // Synchronous active-low reset
        repeat (5) @(posedge i_clk);

        @(negedge i_clk);
        i_rst_n = 1'b1;

        repeat (5) @(posedge i_clk);

        // Check UART TX idle state after reset.
        checks = checks + 1;

        if (o_uart_tx !== 1'b1) begin
            errors = errors + 1;
            $display(
                "ERROR: UART TX is not HIGH after reset"
            );
        end

        // Run all UART-level requests continuously.
        // Error LFSR and noise LFSR are not reseeded
        // between normal DSP transactions.
        for (
            request_index = 0;
            request_index < NUM_REQUESTS;
            request_index = request_index + 1
        ) begin
            check_request(request_index);
        end

        $display(
            "------------------------------------------------------------"
        );

        $display(
            "fpga_top end-to-end requests: %0d",
            NUM_REQUESTS
        );

        $display(
            "fpga_top checks: %0d, errors: %0d",
            checks,
            errors
        );

        if (errors == 0) begin
            $display(
                "PASS: tb_fpga_top"
            );
        end
        else begin
            $display(
                "FAIL: tb_fpga_top"
            );
        end

        $finish;
    end

endmodule

`default_nettype wire