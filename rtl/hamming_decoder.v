`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/25/2026 07:54:57 AM
// Design Name: 
// Module Name: hamming_decoder
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// Extended Hamming SECDED (8,4) decoder.
// Mapping: {p0,d3,d2,d1,p3,d0,p2,p1}
// Registered output: valid one cycle after accepted i_valid.
// Status: 00=no error, 01=single bit corrected, 10=double bit detected.
`default_nettype none
module hamming_decoder(
    input wire      i_clk,
    input wire      i_rst_n,
    input wire [7:0]     i_codeword,
    input wire      i_valid,
    
    output reg [3:0] o_data,
    output reg [1:0] o_status,
    output reg       o_valid
);

// codeword mapping:
//[7] = p0; overall parity 
//[6] = d3; 111
//[5] = d2; 110
//[4] = d1; 101
//[3] = p3; 100
//[2] = d0; 011
//[1] = p2; 010
//[0] = p1; 001

    wire [2:0] w_syndrome;
    wire       w_parity;
    reg [7:0] r_corrected;
    reg [3:0] r_decoded;
    reg [1:0] r_status;

    //S1 = p1 ^ d0 ^ d1 ^ d3
    assign w_syndrome[0] =  i_codeword[0] ^ i_codeword[2] ^ i_codeword[4] ^ i_codeword[6];
    //S2 = p2 ^ d0 ^ d2 ^ d3
    assign w_syndrome[1] = i_codeword[1] ^ i_codeword[2] ^ i_codeword[5] ^ i_codeword[6];
    //S3 = p3 ^ d1 ^ d2 ^ d3
    assign w_syndrome[2] = i_codeword[3] ^ i_codeword[4] ^ i_codeword[5] ^ i_codeword[6];

    assign w_parity = ^i_codeword;

    always @ (*) begin
        r_corrected = i_codeword;
        r_status = 2'b0;
        r_decoded = 4'd0;

        // Non-zero	1	Flip codeword bit S-1 (bit 0..6)	01
        if(w_syndrome != 3'b000 && w_parity) begin

        //Syndrome 1-7 maps to codeword 0-6, 1<= w_syndrome <= 7 mapping to i_codeword[0]-i_codeword[6]
            r_corrected[w_syndrome - 3'd1] = ~i_codeword[w_syndrome - 3'd1];
            r_status = 2'b01;
        end
        // 000	1	Flip bit 7 (p0)	01
        else if(w_syndrome == 3'b000 && w_parity) begin
            r_status = 2'b01;

            // Overall parity bit error (bit 7).
            r_corrected[7] =  ~i_codeword[7];
        end
        // Non-zero	0	Detect double-bit error; do not correct	10
        else if(w_syndrome != 3'b000 && !w_parity) begin
            // Double error: diagnostic data = 0; leave word uncorrected.
            r_status = 2'b10;
        end
        
        if(r_status != 2'b10) begin
            r_decoded = {r_corrected[6], r_corrected[5], r_corrected[4], r_corrected[2]};
        end
    end

    always @ (posedge i_clk) begin
        if(~i_rst_n) begin
            o_data <= 4'b0;
            o_valid <= 1'b0;
            o_status <= 2'b00;
        end
        else begin
            // Align output valid timing with registered data
            o_valid <= i_valid;
            if(i_valid) begin
            o_data <= r_decoded;
            o_status <= r_status;
            end
        end
    end

endmodule

`default_nettype wire