
`timescale 1ns/1ps

module bpsk_modulator_tb;

    reg i_clk;
    reg i_rst_n;
    reg [7:0] i_codeword;
    reg i_valid;

    wire signed [7:0] o_sample;
    wire o_valid;
    wire o_done;

    integer test_num;
    integer sample_count;
    integer errors;
    integer expected_sample;
    integer bit_pos;

    // Instantiate DUT
    bpsk_modulator dut (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_codeword(i_codeword),
        .i_valid(i_valid),
        .o_sample(o_sample),
        .o_valid(o_valid),
        .o_done(o_done)
    );

    // 50 MHz clock, period = 20 ns
    initial i_clk = 0;
    always #10 i_clk = ~i_clk;

    initial begin
        i_rst_n = 0;
        i_valid = 0;
        i_codeword = 0;
        errors = 0;

        #40;
        @(negedge i_clk);
        i_rst_n = 1;

        // Test all 256 codewords
        for (test_num = 0; test_num < 256; test_num = test_num + 1) begin

            @(negedge i_clk);
            i_codeword = test_num;
            i_valid = 1;

            @(negedge i_clk);
            i_valid = 0;

            sample_count = 0;

            while (sample_count < 64) begin
                @(negedge i_clk);

                if (o_valid) begin
                    bit_pos = 7 - (sample_count / 8);

                    if (i_codeword[bit_pos])
                        expected_sample = -127;
                    else
                        expected_sample = 127;

                    if (o_sample !== expected_sample) begin
                        $display("FAIL: codeword=%b sample=%0d expected=%0d got=%0d",
                                 i_codeword, sample_count,
                                 expected_sample, o_sample);
                        errors = errors + 1;
                    end

                    if (o_done !== (sample_count == 63)) begin
                        $display("FAIL: o_done at sample %0d", sample_count);
                        errors = errors + 1;
                    end

                    sample_count = sample_count + 1;
                end
            end

            $display("PASS: codeword=%b, 64 samples checked", i_codeword);
        end

        if (errors == 0)
            $display("TEST PASSED: All 256 codewords passed!");
        else
            $display("TEST FAILED: %0d errors", errors);

        $finish;
    end

    initial begin
        #1000000;
        $display("TIMEOUT: Simulation exceeded time limit");
        $finish;
    end

endmodule
