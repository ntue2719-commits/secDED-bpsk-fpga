
`timescale 1ns/1ps

module bpsk_demodulator_tb;

    //================================================
    // DUT signals
    //================================================
    reg                 i_clk;
    reg                 i_rst_n;
    reg signed [7:0]    i_sample;
    reg                 i_valid;
    reg                 i_done;

    wire [7:0]          o_codeword;
    wire                o_valid;

    //================================================
    // Test variables
    //================================================
    integer test_count;
    integer error_count;
    integer k;
    integer b;
    integer s;

    reg [7:0] expected_codeword;

    //================================================
    // DUT
    //================================================
    bpsk_demodulator dut (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_sample   (i_sample),
        .i_valid    (i_valid),
        .i_done     (i_done),
        .o_codeword (o_codeword),
        .o_valid    (o_valid)
    );

    //================================================
    // 50 MHz clock
    // Period = 20 ns
    //================================================
    initial begin
        i_clk = 1'b0;
        forever #10 i_clk = ~i_clk;
    end

    //================================================
    // Waveform generation for EPWave
    //================================================
    initial begin
        $dumpfile("bpsk_demodulator.vcd");
        $dumpvars(0, bpsk_demodulator_tb);
    end

    //================================================
    // Error reporting
    //================================================
    task report_error;
        input [8*100-1:0] message;
        begin
            $display("[%0t] ERROR: %0s", $time, message);
            error_count = error_count + 1;
        end
    endtask

    //================================================
    // Reset task
    //================================================
    task reset_dut;
        begin
            @(negedge i_clk);

            i_rst_n  = 1'b0;
            i_sample = 8'sd0;
            i_valid  = 1'b0;
            i_done   = 1'b0;

            repeat (3) @(negedge i_clk);

            i_rst_n = 1'b1;

            @(posedge i_clk);
            #1;

            if (o_valid !== 1'b0)
                report_error("o_valid is not zero after reset");

            if (o_codeword !== 8'd0)
                report_error("o_codeword is not zero after reset");

            @(negedge i_clk);
        end
    endtask

    //================================================
    // Insert one idle clock cycle
    //================================================
    task idle_cycle;
        begin
            @(negedge i_clk);

            i_valid  = 1'b0;
            i_done   = 1'b0;
            i_sample = 8'sd0;

            @(posedge i_clk);
            #1;

            if (o_valid !== 1'b0)
                report_error("Unexpected o_valid during idle cycle");
        end
    endtask

    //================================================
    // Send one complete BPSK codeword
    //
    // 0 -> +127
    // 1 -> -127
    //
    // 8 samples per bit
    // 8 bits per codeword
    // MSB first
    //
    // i_done asserted with the 64th sample
    //================================================
    task send_codeword;
        input [7:0] tx_codeword;

        integer bit_no;
        integer sample_no;

        begin
            expected_codeword = tx_codeword;

            $display("");
            $display("----------------------------------------");
            $display("[%0t] Sending codeword: %08b",
                     $time, tx_codeword);

            for (bit_no = 7; bit_no >= 0;
                 bit_no = bit_no - 1) begin

                for (sample_no = 0; sample_no < 8;
                     sample_no = sample_no + 1) begin

                    // Insert idle cycles to test i_valid gaps
                    if (((bit_no * 8 + sample_no) % 5) == 2)
                        idle_cycle;

                    @(negedge i_clk);

                    i_valid = 1'b1;

                    // done must accompany sample 64
                    i_done = (bit_no == 0) &&
                             (sample_no == 7);

                    if (tx_codeword[bit_no] == 1'b0)
                        i_sample = 8'sd127;
                    else
                        i_sample = -8'sd127;

                    @(posedge i_clk);
                    #1;

                    // Check that valid does not assert early
                    if ((bit_no != 0 || sample_no != 7) &&
                        (o_valid !== 1'b0)) begin

                        report_error(
                            "o_valid asserted before final sample"
                        );
                    end

                    // Check final sample
                    if ((bit_no == 0) && (sample_no == 7)) begin

                        if (o_valid !== 1'b1)
                            report_error(
                                "o_valid was not asserted after sample 64"
                            );

                        if (o_codeword !== expected_codeword) begin
                            $display(
                                "[%0t] Expected: %08b, Received: %08b",
                                $time,
                                expected_codeword,
                                o_codeword
                            );

                            report_error("Incorrect decoded codeword");
                        end
                        else if (o_valid === 1'b1) begin
                            $display(
                                "[%0t] PASS: decoded codeword = %08b",
                                $time,
                                o_codeword
                            );
                        end
                    end
                end
            end

            // Return DUT inputs to idle
            @(negedge i_clk);

            i_valid  = 1'b0;
            i_done   = 1'b0;
            i_sample = 8'sd0;

            test_count = test_count + 1;

            // Check that o_valid is a one-cycle pulse
            @(posedge i_clk);
            #1;

            if (o_valid !== 1'b0)
                report_error(
                    "o_valid did not deassert after final sample"
                );

        end
    endtask

    //================================================
    // Main test sequence
    //================================================
    initial begin

        i_rst_n          = 1'b0;
        i_sample         = 8'sd0;
        i_valid          = 1'b0;
        i_done           = 1'b0;

        test_count       = 0;
        error_count      = 0;
        expected_codeword = 8'd0;

        // Reset verification
        reset_dut;

        //============================================
        // Directed test cases
        //============================================
        send_codeword(8'b00000000);
        send_codeword(8'b11111111);
        send_codeword(8'b10101010);
        send_codeword(8'b01010101);
        send_codeword(8'b10000001);
        send_codeword(8'b01111110);
        send_codeword(8'b00001111);
        send_codeword(8'b11110000);

        //============================================
        // Walking-one test cases
        //============================================
        for (k = 0; k < 8; k = k + 1)
            send_codeword(8'b00000001 << k);

        //============================================
        // Walking-zero test cases
        //============================================
        for (k = 0; k < 8; k = k + 1)
            send_codeword(~(8'b00000001 << k));

        //============================================
        // Random test cases
        //============================================
        for (k = 0; k < 32; k = k + 1)
            send_codeword($random);

        //============================================
        // Final report
        //============================================
        $display("");
        $display("========================================");
        $display("BPSK DEMODULATOR TEST SUMMARY");
        $display("========================================");
        $display("Total tests : %0d", test_count);
        $display("Total errors: %0d", error_count);

        if (error_count == 0)
            $display("PASS: bpsk_demodulator_tb");
        else
            $display("FAIL: bpsk_demodulator_tb");

        $display("========================================");

        $finish;
    end

    //================================================
    // Simulation timeout
    //================================================
    initial begin
        #2000000;

        $display("");
        $display("ERROR: Simulation timeout");
        $display("Simulation did not finish within 2 ms.");

        $finish;
    end

endmodule
