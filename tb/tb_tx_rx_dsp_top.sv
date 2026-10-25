`timescale 1ns / 1ps
`default_nettype none

// ============================================================
// Module      : tb_tx_rx_dsp_top
// Description : Self-checking testbench for tx_rx_dsp_top.v
// Reference   : Uses data/input_data.hex, data/config.hex,
//               data/decoded.hex, data/status.hex
// ============================================================

module tb_tx_rx_dsp_top;
    localparam integer CLK_PERIOD_NS = 20;
    localparam integer TRANSACTIONS  = 384;

    reg        i_clk         = 1'b0;
    reg        i_rst_n       = 1'b0;
    reg  [3:0] i_data        = 4'h0;
    reg  [2:0] i_noise_level = 3'd0;
    reg  [1:0] i_err_mode    = 2'b00;
    reg        i_start       = 1'b0;

    wire [3:0] o_data;
    wire [1:0] o_status;
    wire       o_done;

    reg [7:0] input_data_ref [0:TRANSACTIONS-1];
    reg [7:0] config_ref     [0:TRANSACTIONS-1];
    reg [7:0] decoded_ref    [0:TRANSACTIONS-1];
    reg [7:0] status_ref     [0:TRANSACTIONS-1];

    integer test_count  = 0;
    integer error_count = 0;
    integer i;
    integer timeout;

    always #(CLK_PERIOD_NS/2) i_clk = ~i_clk;

    tx_rx_dsp_top dut (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_data        (i_data),
        .i_noise_level (i_noise_level),
        .i_err_mode    (i_err_mode),
        .i_start       (i_start),
        .o_data        (o_data),
        .o_status      (o_status),
        .o_done        (o_done)
    );

    task automatic check_result(
        input [3:0]  expected_data,
        input [1:0]  expected_status,
        input string description
    );
    begin
        test_count = test_count + 1;
        if (o_data !== expected_data || o_status !== expected_status) begin
            error_count = error_count + 1;
            $display("FAIL [%0t] %s: data=%01h (exp %01h), status=%02b (exp %02b)",
                     $time, description, o_data, expected_data, o_status, expected_status);
        end
    end
    endtask

    initial begin
        // Load verification vectors exported by Python golden model
        $readmemh("data/input_data.hex", input_data_ref);
        $readmemh("data/config.hex", config_ref);
        $readmemh("data/decoded.hex", decoded_ref);
        $readmemh("data/status.hex", status_ref);

        // Verify initial reset values
        repeat (3) @(posedge i_clk);
        #1;
        test_count = test_count + 1;
        if (o_done !== 1'b0 || o_data !== 4'h0 || o_status !== 2'b00) begin
            error_count = error_count + 1;
            $display("FAIL [%0t] Initial reset state incorrect", $time);
        end

        @(negedge i_clk);
        i_rst_n = 1'b1;

        // Run through all 384 golden transactions
        for (i = 0; i < TRANSACTIONS; i = i + 1) begin
            @(negedge i_clk);
            i_data        = input_data_ref[i][3:0];
            i_noise_level = config_ref[i][4:2];
            i_err_mode    = config_ref[i][1:0];
            i_start       = 1'b1;

            @(negedge i_clk);
            i_start = 1'b0;

            // Wait for o_done completion pulse
            timeout = 0;
            while (!o_done && timeout < 200) begin
                @(posedge i_clk);
                timeout = timeout + 1;
            end

            if (timeout >= 200) begin
                error_count = error_count + 1;
                $display("FAIL [%0t] Transaction %0d: Timeout waiting for o_done!", $time, i);
            end else begin
                #1; // Sample immediately when o_done asserts
                check_result(decoded_ref[i][3:0], status_ref[i][1:0], $sformatf("Tx %0d (data=%01h, n=%0d, err=%0d)", 
                             i, input_data_ref[i][3:0], config_ref[i][4:2], config_ref[i][1:0]));
            end

            // Allow 2 clock cycles gap before next transaction
            repeat (2) @(posedge i_clk);
        end

        $display("----------------------------------------------------------");
        $display("tx_rx_dsp_top checks: %0d, errors: %0d", test_count, error_count);
        if (error_count == 0)
            $display("PASS: tb_tx_rx_dsp_top (All %0d DSP transactions matched!)", TRANSACTIONS);
        else
            $fatal(1, "FAIL: tb_tx_rx_dsp_top (%0d errors)", error_count);

        $finish;
    end

endmodule

`default_nettype wire
