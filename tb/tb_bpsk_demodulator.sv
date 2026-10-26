`timescale 1ns/1ps

module bpsk_demodulator_tb;

    // DUT inputs
    reg         i_clk;
    reg         i_rst_n;
    reg signed [7:0] i_sample;
    reg         i_valid;
    reg         i_done;

    // DUT outputs
    wire [7:0]  o_codeword;
    wire        o_valid;


    // Test variables
    integer test_count;
    integer error_count;
    integer bit_idx;
    integer sample_idx;

    reg [7:0] expected_codeword;

    // Instantiate DUT
    bpsk_demodulator dut (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),
        .i_sample    (i_sample),
        .i_valid     (i_valid),
        .i_done      (i_done),
        .o_codeword  (o_codeword),
        .o_valid     (o_valid)
    );

    // 50 MHz clock: period = 20 ns
    initial begin
        i_clk = 1'b0;
        forever #10 i_clk = ~i_clk;
    end

    // Reset task
    task reset_dut;
    begin
        @(negedge i_clk);
        i_rst_n  = 1'b0;
        i_sample = 8'sd0;
        i_valid  = 1'b0;
        i_done   = 1'b0;

        repeat (3) @(negedge i_clk);

        i_rst_n = 1'b1;

        @(negedge i_clk);
    end
    endtask

    // --------------------------------------------
    // Send one BPSK codeword
    //
    // bit 0 -> +127, 8 samples
    // bit 1 -> -127, 8 samples
    // MSB first
    // --------------------------------------------
    task send_codeword;
        input [7:0] tx_codeword;
        integer b;
        integer s;
    begin
        expected_codeword = tx_codeword;

        $display("----------------------------------------");
        $display("[%0t] TX codeword = %08b",
                 $time, tx_codeword);

        // Send 8 bits, MSB first
        for (b = 7; b >= 0; b = b - 1) begin

            // Each bit has 8 samples
            for (s = 0; s < 8; s = s + 1) begin
                @(negedge i_clk);

                i_valid = 1'b1;
                i_done  = 1'b0;

                if (tx_codeword[b] == 1'b0)
                    i_sample = 8'sd127;
                else
                    i_sample = -8'sd127;

                @(posedge i_clk);
                #1;

                // o_valid must not assert early
                if ((b != 0 || s != 7) &&
                    (o_valid !== 1'b0)) begin

                    $display(
                        "[%0t] FAIL: o_valid asserted early",
                        $time
                    );

                    error_count = error_count + 1;
                end
            end
        end

        // After the 64th sample
        if (o_valid !== 1'b1) begin
            $display(
                "[%0t] FAIL: o_valid was not asserted",
                $time
            );

            error_count = error_count + 1;
        end

        if (o_codeword !== expected_codeword) begin
            $display(
                "[%0t] FAIL: expected=%08b, received=%08b",
                $time, expected_codeword, o_codeword
            );

            error_count = error_count + 1;
        end
        else if (o_valid === 1'b1) begin
            $display(
                "[%0t] PASS: codeword=%08b, o_valid=1",
                $time, o_codeword
            );
        end

        test_count = test_count + 1;

        // Stop sending samples
        i_valid  = 1'b0;
        i_sample = 8'sd0;

        // Check that o_valid is a one-cycle pulse
        @(posedge i_clk);
        #1;

        if (o_valid !== 1'b0) begin
            $display(
                "[%0t] FAIL: o_valid pulse is longer than 1 clock",
                $time
            );

            error_count = error_count + 1;
        end

        @(negedge i_clk);
    end
    endtask

    // --------------------------------------------
    // Main test sequence
    // --------------------------------------------
    initial begin
        test_count = 0;
        error_count = 0;

        i_rst_n  = 1'b0;
        i_sample = 8'sd0;
        i_valid  = 1'b0;
        i_done   = 1'b0;

        $display("");
        $display("========================================");
        $display(" BPSK DEMODULATOR TESTBENCH");
        $display(" Clock     : 50 MHz");
        $display(" Samples   : 64 per codeword");
        $display(" BPSK 0    : +127");
        $display(" BPSK 1    : -127");
        $display("========================================");

        reset_dut;

        // Test 1: All zeros
        send_codeword(8'b00000000);

        // Test 2: All ones
        send_codeword(8'b11111111);

        // Test 3: Alternating bits
        send_codeword(8'b10101010);

        // Test 4: Inverse alternating bits
        send_codeword(8'b01010101);

        // Test 5: Mixed patterns
        send_codeword(8'b11010011);
        send_codeword(8'b00101100);
        send_codeword(8'b10000001);
        send_codeword(8'b01111110);

        // Test 9: Additional patterns
        send_codeword(8'b11110000);
        send_codeword(8'b00001111);
        send_codeword(8'b10011010);

        // ----------------------------------------
        // Summary
        // ----------------------------------------
        $display("");
        $display("========================================");
        $display(" TEST SUMMARY");
        $display(" Total transactions : %0d", test_count);
        $display(" Total errors       : %0d", error_count);

        if (error_count == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: TEST FAILED");

        $display("========================================");
        $finish;
    end

    // --------------------------------------------
    // Simulation timeout
    // --------------------------------------------
    initial begin
        #2000000;

        $display("ERROR: Simulation timeout");
        $finish;
    end
endmodule