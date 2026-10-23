`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/23/2026 08:43:57 PM
// Design Name: 
// Module Name: tb_hamming_encoder
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
// Self-checking testbench for hamming_encoder.v
// Uses data/encoded.hex exported by python/export_hex.py.
// Dataset ordering: index = data * 24 + noise_level * 3 + err_mode.
// The first entry for each payload is therefore encoded_ref[data * 24].

`default_nettype none
module tb_hamming_encoder;
    localparam integer CLK_PERIOD_NS = 20;
    localparam integer TRANSACTIONS  = 384;

    reg         i_clk   = 1'b0;
    reg         i_rst_n = 1'b0;
    reg  [3:0]  i_data  = 4'h0;
    reg         i_start = 1'b0;
    wire [7:0]  o_codeword;
    wire        o_valid;

    reg [7:0] encoded_ref [0:TRANSACTIONS-1];
    integer test_count = 0;
    integer error_count = 0;
    integer d;
    reg [7:0] expected;

    always #(CLK_PERIOD_NS/2) i_clk = ~i_clk;

    hamming_encoder dut (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_data     (i_data),
        .i_start    (i_start),
        .o_codeword (o_codeword),
        .o_valid    (o_valid)
    );

    task automatic check_output(
        input bit expected_valid,
        input [7:0] expected_word,
        input bit check_word,
        input string description
    );
    begin
        test_count = test_count + 1;
        if (o_valid !== expected_valid ||
            (check_word && o_codeword !== expected_word)) begin
            error_count = error_count + 1;
            $display("FAIL [%0t] %s: valid=%b expected=%b, codeword=%02h expected=%02h",
                     $time, description, o_valid, expected_valid,
                     o_codeword, expected_word);
        end
    end
    endtask

    task automatic run_payload(input [3:0] payload);
        reg [7:0] ref_word;
    begin
        ref_word = encoded_ref[integer'(payload) * 24];
        // Drive ahead of rising edge to avoid testbench/DUT races.
        @(negedge i_clk);
        i_data  = payload;
        i_start = 1'b1;

        // Edge N: request accepted, no output yet.
        @(posedge i_clk); #1;
        check_output(1'b0, 8'h00, 1'b0, "accept request");

        // Keep start high at N+1 with different data: request must be ignored
        // while pending. This also exercises the busy behavior.
        @(negedge i_clk);
        i_data  = ~payload;
        i_start = 1'b1;

        // Edge N+1: expected result becomes valid.
        @(posedge i_clk); #1;
        check_output(1'b1, ref_word, 1'b1, "encoded output");

        @(negedge i_clk);
        i_start = 1'b0;

        // Edge N+2: valid must clear and result must remain stable.
        @(posedge i_clk); #1;
        check_output(1'b0, ref_word, 1'b1, "valid clears / output holds");

        // Edge N+3: no extra result due to the ignored busy request.
        @(posedge i_clk); #1;
        check_output(1'b0, ref_word, 1'b1, "no ghost response");
    end
    endtask

    initial begin
        $readmemh("D:/FPGA_Project/secDED/secDED-bpsk-fpga/data/encoded.hex", encoded_ref);

        repeat (3) @(posedge i_clk);
        #1;
        check_output(1'b0, 8'h00, 1'b1, "reset values");

        @(negedge i_clk);
        i_rst_n = 1'b1;

        // All 16 payloads. The 384-row dataset repeats each payload 24 times.
        for (d = 0; d < 16; d = d + 1)
            run_payload(d[3:0]);

        // Reset while a request is pending: it must be canceled.
        @(negedge i_clk);
        i_data  = 4'hA;
        i_start = 1'b1;
        @(posedge i_clk); #1;
        check_output(1'b0, 8'h00, 1'b0, "pending request accepted");
        @(negedge i_clk);
        i_start = 1'b0;
        i_rst_n = 1'b0;
        #1;
        check_output(1'b0, 8'h00, 1'b1, "asynchronous reset");
        @(posedge i_clk); #1;
        check_output(1'b0, 8'h00, 1'b1, "held reset");
        @(negedge i_clk);
        i_rst_n = 1'b1;
        @(posedge i_clk); #1;
        check_output(1'b0, 8'h00, 1'b1, "pending request discarded");

        $display("Hamming encoder checks: %0d, errors: %0d", test_count, error_count);
        if (error_count == 0)
            $display("PASS: tb_hamming_encoder");
        else
            $fatal(1, "FAIL: tb_hamming_encoder (%0d errors)", error_count);
        $finish;
    end
endmodule

`default_nettype wire

