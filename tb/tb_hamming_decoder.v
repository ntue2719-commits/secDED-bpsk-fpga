`timescale 1ns / 1ps
`default_nettype none

module tb_hamming_decoder;
    reg clk = 1'b0;
    always #10 clk = ~clk;  // 50 MHz
    reg rst_n = 1'b0;
    reg [7:0] i_codeword = 8'h00;
    reg i_valid = 1'b0;
    wire [3:0] o_data;
    wire [1:0] o_status;
    wire o_valid;
    integer checks = 0, errors = 0;
    integer d, b1, b2, t;

    reg [7:0] encoded_ref [0:383];
    reg [7:0] demod_ref   [0:383];
    reg [7:0] decoded_ref [0:383];
    reg [7:0] status_ref  [0:383];

    hamming_decoder dut (
        .i_clk(clk), .i_rst_n(rst_n), .i_codeword(i_codeword),
        .i_valid(i_valid), .o_data(o_data),
        .o_status(o_status), .o_valid(o_valid)
    );

    task automatic expect_result(
        input [7:0] codeword,
        input [3:0] exp_data,
        input [1:0] exp_status
    );
    begin
        @(negedge clk);
        i_codeword = codeword;
        i_valid = 1'b1;
        @(posedge clk);
        #1;
        checks = checks + 1;
        if (o_valid !== 1'b1 || o_data !== exp_data || o_status !== exp_status) begin
            errors = errors + 1;
            $display("FAIL check=%0d cw=%02h expected data=%h status=%b got valid=%b data=%h status=%b",
                     checks, codeword, exp_data, exp_status, o_valid, o_data, o_status);
        end
        @(negedge clk);
        i_valid = 1'b0;
        @(posedge clk);
        #1;
        checks = checks + 1;
        if (o_valid !== 1'b0 || o_data !== exp_data || o_status !== exp_status) begin
            errors = errors + 1;
            $display("FAIL hold check=%0d", checks);
        end
    end
    endtask

    initial begin
        // Vivado must resolve these relative paths from the simulation run directory.
        // Set them to absolute paths if your Vivado project runs elsewhere.
        $readmemh("D:/FPGA_Project/secDED/secDED-bpsk-fpga/data/encoded.hex", encoded_ref);
        $readmemh("D:/FPGA_Project/secDED/secDED-bpsk-fpga/data/demodulated.hex", demod_ref);
        $readmemh("D:/FPGA_Project/secDED/secDED-bpsk-fpga/data/decoded.hex", decoded_ref);
        $readmemh("D:/FPGA_Project/secDED/secDED-bpsk-fpga/data/status.hex", status_ref);

        repeat (3) @(negedge clk);
        #1;
        checks = checks + 1;
        if (o_valid !== 0 || o_data !== 0 || o_status !== 0) begin
            errors = errors + 1;
            $display("FAIL reset");
        end
        rst_n = 1'b1;

        // Exhaustive no-error and all 8 single-bit positions.
        for (d = 0; d < 16; d = d + 1) begin
            expect_result(encoded_ref[d*24], d[3:0], 2'b00);
            for (b1 = 0; b1 < 8; b1 = b1 + 1)
                expect_result(encoded_ref[d*24] ^ (8'h01 << b1), d[3:0], 2'b01);
        end

        // Exhaustive 28 unique double-bit combinations for each payload.
        for (d = 0; d < 16; d = d + 1)
            for (b1 = 0; b1 < 8; b1 = b1 + 1)
                for (b2 = b1 + 1; b2 < 8; b2 = b2 + 1)
                    expect_result(encoded_ref[d*24] ^ (8'h01 << b1) ^ (8'h01 << b2), 4'h0, 2'b10);

        // End-to-end Python reference vectors: 384 consecutive transactions.
        for (t = 0; t < 384; t = t + 1)
            expect_result(demod_ref[t], decoded_ref[t][3:0], status_ref[t][1:0]);

        // Reset between requests.
        @(negedge clk);
        rst_n = 1'b0;
        #1;
        checks = checks + 1;
        if (o_valid !== 0 || o_data !== 0 || o_status !== 0) begin
            errors = errors + 1;
            $display("FAIL second reset");
        end

        $display("Hamming decoder checks: %0d, errors: %0d", checks, errors);
        if (errors == 0) $display("PASS: tb_hamming_decoder");
        else $fatal(1, "FAIL: tb_hamming_decoder");
        $finish;
    end
endmodule
`default_nettype wire
