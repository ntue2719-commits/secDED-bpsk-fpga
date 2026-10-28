`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/28/2026 10:12:11 PM
// Design Name: 
// Module Name: tb_tx_rx_dsp_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module tb_tx_rx_dsp_top;

    localparam integer NUM_TRANSACTIONS = 384;
    localparam integer SAMPLES_PER_TRANSACTION = 64;
    localparam integer NUM_SAMPLES = NUM_TRANSACTIONS * SAMPLES_PER_TRANSACTION;
    localparam integer MAX_CYCLES_PER_TRANSACTION = 200;

    // Absolute path used for Vivado/XSim on the current machine.
    // Change only this line if the repository is moved.
    localparam string DATA_DIR = "D:/FPGA_Project/secDED/secDED-bpsk-fpga/data";

    reg         i_clk;
    reg         i_rst_n;
    reg  [3:0]  i_data;
    reg  [2:0]  i_noise_level;
    reg  [1:0]  i_err_mode;
    reg         i_start;

    wire [3:0]  o_data;
    wire [1:0]  o_status;
    wire        o_done;

    // Transaction-level golden vectors
    reg [7:0] input_data_mem         [0:NUM_TRANSACTIONS-1];
    reg [7:0] config_mem             [0:NUM_TRANSACTIONS-1];
    reg [7:0] encoded_mem            [0:NUM_TRANSACTIONS-1];
    reg [7:0] corrupted_mem          [0:NUM_TRANSACTIONS-1];
    reg [7:0] demodulated_mem        [0:NUM_TRANSACTIONS-1];
    reg [7:0] decoded_mem            [0:NUM_TRANSACTIONS-1];
    reg [7:0] status_mem             [0:NUM_TRANSACTIONS-1];
    reg [7:0] syndrome_mem           [0:NUM_TRANSACTIONS-1];
    reg [7:0] corrected_mem          [0:NUM_TRANSACTIONS-1];
    reg [7:0] error_lfsr_before_mem  [0:NUM_TRANSACTIONS-1];
    reg [7:0] error_lfsr_after_mem   [0:NUM_TRANSACTIONS-1];
    reg [7:0] noise_lfsr_before_mem  [0:NUM_TRANSACTIONS-1];
    reg [7:0] noise_lfsr_after_mem   [0:NUM_TRANSACTIONS-1];

    // Sample-level golden vectors
    reg [7:0] bpsk_tx_mem            [0:NUM_SAMPLES-1];
    reg [7:0] noise_values_mem       [0:NUM_SAMPLES-1];
    reg [7:0] bpsk_noisy_mem         [0:NUM_SAMPLES-1];

    integer checks;
    integer errors;

    integer encoded_idx;
    integer corrupted_idx;
    integer bpsk_idx;
    integer noise_input_idx;
    integer noisy_idx;
    integer demod_idx;
    integer decoded_idx;
    integer done_idx;

    integer tx;

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

    // 50 MHz clock
    initial begin
        i_clk = 1'b0;
        forever #10 i_clk = ~i_clk;
    end

    task check8;
        input [8*80-1:0] name;
        input [7:0] actual;
        input [7:0] expected;
        input integer index;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("ERROR: %0s[%0d] actual=0x%02h expected=0x%02h time=%0t",
                         name, index, actual, expected, $time);
            end
        end
    endtask

    task check4;
        input [8*80-1:0] name;
        input [3:0] actual;
        input [3:0] expected;
        input integer index;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("ERROR: %0s[%0d] actual=0x%01h expected=0x%01h time=%0t",
                         name, index, actual, expected, $time);
            end
        end
    endtask

    task check3;
        input [8*80-1:0] name;
        input [2:0] actual;
        input [2:0] expected;
        input integer index;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("ERROR: %0s[%0d] actual=0x%01h expected=0x%01h time=%0t",
                         name, index, actual, expected, $time);
            end
        end
    endtask

    task check2;
        input [8*80-1:0] name;
        input [1:0] actual;
        input [1:0] expected;
        input integer index;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("ERROR: %0s[%0d] actual=0x%01h expected=0x%01h time=%0t",
                         name, index, actual, expected, $time);
            end
        end
    endtask

    task check1;
        input [8*80-1:0] name;
        input actual;
        input expected;
        input integer index;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("ERROR: %0s[%0d] actual=%0b expected=%0b time=%0t",
                         name, index, actual, expected, $time);
            end
        end
    endtask

    // Drive one complete DSP transaction.
    task run_transaction;
        input integer index;
        integer cycles;
        begin
            // Check continuous LFSR state before starting this transaction.
            check8("error_lfsr_before",
                   dut.u_bit_flip_channel.r_lfsr,
                   error_lfsr_before_mem[index], index);

            check8("noise_lfsr_before",
                   dut.u_lfsr_noise_injector.noise_lfsr,
                   noise_lfsr_before_mem[index], index);

            // CONFIG = {3'b000, noise_level[2:0], err_mode[1:0]}
            check3("config_reserved", config_mem[index][7:5], 3'b000, index);
            check4("input_data_upper", input_data_mem[index][7:4], 4'b0000, index);

            @(negedge i_clk);
            i_data        = input_data_mem[index][3:0];
            i_noise_level = config_mem[index][4:2];
            i_err_mode    = config_mem[index][1:0];
            i_start       = 1'b1;

            @(negedge i_clk);
            i_start = 1'b0;

            // Wait for transaction-level completion with timeout protection.
            cycles = 0;
            while ((o_done !== 1'b1) && (cycles < MAX_CYCLES_PER_TRANSACTION)) begin
                @(negedge i_clk);
                cycles = cycles + 1;
            end

            if (o_done !== 1'b1) begin
                errors = errors + 1;
                $display("ERROR: transaction %0d timeout after %0d cycles", index, cycles);
                $finish;
            end

            // Allow the negedge stage monitor to finish first.
            #1;

            // Top-level result must be valid with o_done.
            check4("top_decoded", o_data, decoded_mem[index][3:0], index);
            check2("top_status", o_status, status_mem[index][1:0], index);
            check1("top_done", o_done, 1'b1, index);

            // Move beyond the one-cycle done pulse before next transaction.
            @(negedge i_clk);
            #1;
            check1("top_done_pulse", o_done, 1'b0, index);
        end
    endtask

    // Noise input monitor.
    // At this posedge the noise injector consumes the current BPSK sample.
    // signed_noise is based on the current LFSR state before the sequential update.
    always @(posedge i_clk) begin
        if (i_rst_n && dut.w_bpsk_valid) begin
            if (noise_input_idx < NUM_SAMPLES) begin
                check8("noise_input_bpsk",
                       dut.w_bpsk_sample[7:0],
                       bpsk_tx_mem[noise_input_idx], noise_input_idx);

                check8("noise_value",
                       dut.u_lfsr_noise_injector.signed_noise[7:0],
                       noise_values_mem[noise_input_idx], noise_input_idx);

                if ((noise_input_idx % SAMPLES_PER_TRANSACTION) == 0) begin
                    check8("noise_lfsr_first_sample",
                           dut.u_lfsr_noise_injector.noise_lfsr,
                           noise_lfsr_before_mem[noise_input_idx / SAMPLES_PER_TRANSACTION],
                           noise_input_idx / SAMPLES_PER_TRANSACTION);
                end

                noise_input_idx = noise_input_idx + 1;
            end
            else begin
                errors = errors + 1;
                $display("ERROR: more than %0d BPSK samples consumed by noise injector", NUM_SAMPLES);
            end
        end
    end

    // Stage-by-stage monitor after sequential outputs have settled.
    always @(negedge i_clk) begin
        if (i_rst_n) begin

            // Hamming Encoder
            if (dut.w_encoded_valid) begin
                if (encoded_idx < NUM_TRANSACTIONS) begin
                    check8("encoded",
                           dut.w_encoded_word,
                           encoded_mem[encoded_idx], encoded_idx);
                    encoded_idx = encoded_idx + 1;
                end
                else begin
                    errors = errors + 1;
                    $display("ERROR: extra encoded output");
                end
            end

            // Bit Flip Channel
            if (dut.w_corrupted_valid) begin
                if (corrupted_idx < NUM_TRANSACTIONS) begin
                    check8("corrupted",
                           dut.w_corrupted_word,
                           corrupted_mem[corrupted_idx], corrupted_idx);

                    // r_lfsr has already advanced when o_valid is observed here.
                    check8("error_lfsr_after",
                           dut.u_bit_flip_channel.r_lfsr,
                           error_lfsr_after_mem[corrupted_idx], corrupted_idx);

                    corrupted_idx = corrupted_idx + 1;
                end
                else begin
                    errors = errors + 1;
                    $display("ERROR: extra corrupted output");
                end
            end

            // BPSK Modulator
            if (dut.w_bpsk_valid) begin
                if (bpsk_idx < NUM_SAMPLES) begin
                    check8("bpsk_tx",
                           dut.w_bpsk_sample[7:0],
                           bpsk_tx_mem[bpsk_idx], bpsk_idx);

                    check1("bpsk_done",
                           dut.w_bpsk_done,
                           ((bpsk_idx % SAMPLES_PER_TRANSACTION) == 63),
                           bpsk_idx);

                    bpsk_idx = bpsk_idx + 1;
                end
                else begin
                    errors = errors + 1;
                    $display("ERROR: extra BPSK output sample");
                end
            end

            // LFSR Noise Injector
            if (dut.w_noisy_valid) begin
                if (noisy_idx < NUM_SAMPLES) begin
                    check8("bpsk_noisy",
                           dut.w_noisy_sample[7:0],
                           bpsk_noisy_mem[noisy_idx], noisy_idx);

                    check1("noisy_done",
                           dut.w_noisy_done,
                           ((noisy_idx % SAMPLES_PER_TRANSACTION) == 63),
                           noisy_idx);

                    if ((noisy_idx % SAMPLES_PER_TRANSACTION) == 63) begin
                        check8("noise_lfsr_after",
                               dut.u_lfsr_noise_injector.noise_lfsr,
                               noise_lfsr_after_mem[noisy_idx / SAMPLES_PER_TRANSACTION],
                               noisy_idx / SAMPLES_PER_TRANSACTION);
                    end

                    noisy_idx = noisy_idx + 1;
                end
                else begin
                    errors = errors + 1;
                    $display("ERROR: extra noisy output sample");
                end
            end

            // BPSK Demodulator + combinational Hamming Decoder internals
            if (dut.w_demod_valid) begin
                if (demod_idx < NUM_TRANSACTIONS) begin
                    check8("demodulated",
                           dut.w_demod_word,
                           demodulated_mem[demod_idx], demod_idx);

                    check3("syndrome",
                           dut.u_hamming_decoder.w_syndrome,
                           syndrome_mem[demod_idx][2:0], demod_idx);

                    check8("corrected",
                           dut.u_hamming_decoder.r_corrected,
                           corrected_mem[demod_idx], demod_idx);

                    demod_idx = demod_idx + 1;
                end
                else begin
                    errors = errors + 1;
                    $display("ERROR: extra demodulated output");
                end
            end

            // Hamming Decoder registered output
            if (dut.w_decoded_valid) begin
                if (decoded_idx < NUM_TRANSACTIONS) begin
                    check4("decoded",
                           dut.w_decoded_data,
                           decoded_mem[decoded_idx][3:0], decoded_idx);

                    check2("status",
                           dut.w_decoded_status,
                           status_mem[decoded_idx][1:0], decoded_idx);

                    decoded_idx = decoded_idx + 1;
                end
                else begin
                    errors = errors + 1;
                    $display("ERROR: extra decoded output");
                end
            end

            if (o_done) begin
                done_idx = done_idx + 1;
            end
        end
    end

    initial begin
        checks          = 0;
        errors          = 0;
        encoded_idx     = 0;
        corrupted_idx   = 0;
        bpsk_idx        = 0;
        noise_input_idx = 0;
        noisy_idx       = 0;
        demod_idx       = 0;
        decoded_idx     = 0;
        done_idx        = 0;

        i_rst_n       = 1'b0;
        i_data        = 4'd0;
        i_noise_level = 3'd0;
        i_err_mode    = 2'd0;
        i_start       = 1'b0;

        // Load every HEX file generated by export_hex.py.
        $readmemh($sformatf("%s/input_data.hex", DATA_DIR),        input_data_mem);
        $readmemh($sformatf("%s/config.hex", DATA_DIR),            config_mem);
        $readmemh($sformatf("%s/encoded.hex", DATA_DIR),           encoded_mem);
        $readmemh($sformatf("%s/corrupted.hex", DATA_DIR),         corrupted_mem);
        $readmemh($sformatf("%s/bpsk_tx.hex", DATA_DIR),           bpsk_tx_mem);
        $readmemh($sformatf("%s/noise_values.hex", DATA_DIR),      noise_values_mem);
        $readmemh($sformatf("%s/bpsk_noisy.hex", DATA_DIR),        bpsk_noisy_mem);
        $readmemh($sformatf("%s/demodulated.hex", DATA_DIR),       demodulated_mem);
        $readmemh($sformatf("%s/decoded.hex", DATA_DIR),           decoded_mem);
        $readmemh($sformatf("%s/status.hex", DATA_DIR),            status_mem);
        $readmemh($sformatf("%s/syndrome.hex", DATA_DIR),          syndrome_mem);
        $readmemh($sformatf("%s/corrected.hex", DATA_DIR),         corrected_mem);
        $readmemh($sformatf("%s/error_lfsr_before.hex", DATA_DIR), error_lfsr_before_mem);
        $readmemh($sformatf("%s/error_lfsr_after.hex", DATA_DIR),  error_lfsr_after_mem);
        $readmemh($sformatf("%s/noise_lfsr_before.hex", DATA_DIR), noise_lfsr_before_mem);
        $readmemh($sformatf("%s/noise_lfsr_after.hex", DATA_DIR),  noise_lfsr_after_mem);

        // Synchronous active-low reset.
        repeat (4) @(posedge i_clk);
        @(negedge i_clk);
        i_rst_n = 1'b1;
        #1;

        // Reset-state checks.
        check8("error_lfsr_reset", dut.u_bit_flip_channel.r_lfsr, 8'hA5, 0);
        check8("noise_lfsr_reset", dut.u_lfsr_noise_injector.noise_lfsr, 8'h01, 0);
        check4("top_data_reset", o_data, 4'h0, 0);
        check2("top_status_reset", o_status, 2'b00, 0);
        check1("top_done_reset", o_done, 1'b0, 0);

        // Full DSP matrix: 16 data x 8 noise levels x 3 error modes.
        for (tx = 0; tx < NUM_TRANSACTIONS; tx = tx + 1) begin
            run_transaction(tx);
        end

        // Final count checks.
        if (encoded_idx != NUM_TRANSACTIONS) begin
            errors = errors + 1;
            $display("ERROR: encoded count=%0d expected=%0d", encoded_idx, NUM_TRANSACTIONS);
        end
        if (corrupted_idx != NUM_TRANSACTIONS) begin
            errors = errors + 1;
            $display("ERROR: corrupted count=%0d expected=%0d", corrupted_idx, NUM_TRANSACTIONS);
        end
        if (bpsk_idx != NUM_SAMPLES) begin
            errors = errors + 1;
            $display("ERROR: bpsk sample count=%0d expected=%0d", bpsk_idx, NUM_SAMPLES);
        end
        if (noise_input_idx != NUM_SAMPLES) begin
            errors = errors + 1;
            $display("ERROR: noise input count=%0d expected=%0d", noise_input_idx, NUM_SAMPLES);
        end
        if (noisy_idx != NUM_SAMPLES) begin
            errors = errors + 1;
            $display("ERROR: noisy sample count=%0d expected=%0d", noisy_idx, NUM_SAMPLES);
        end
        if (demod_idx != NUM_TRANSACTIONS) begin
            errors = errors + 1;
            $display("ERROR: demod count=%0d expected=%0d", demod_idx, NUM_TRANSACTIONS);
        end
        if (decoded_idx != NUM_TRANSACTIONS) begin
            errors = errors + 1;
            $display("ERROR: decoded count=%0d expected=%0d", decoded_idx, NUM_TRANSACTIONS);
        end
        if (done_idx != NUM_TRANSACTIONS) begin
            errors = errors + 1;
            $display("ERROR: done count=%0d expected=%0d", done_idx, NUM_TRANSACTIONS);
        end

        $display("------------------------------------------------------------");
        $display("tx_rx_dsp_top checks: %0d, errors: %0d", checks, errors);
        $display("Transactions: %0d", NUM_TRANSACTIONS);
        $display("BPSK/noise samples: %0d", NUM_SAMPLES);

        if (errors == 0)
            $display("PASS: tb_tx_rx_dsp_top");
        else
            $display("FAIL: tb_tx_rx_dsp_top");

        $display("------------------------------------------------------------");
        $finish;
    end

endmodule
