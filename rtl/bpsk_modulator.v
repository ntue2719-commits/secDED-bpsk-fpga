
`timescale 1ns/1ps

module bpsk_modulator (
    input  wire              i_clk,
    input  wire              i_rst_n, 
    input  wire [7:0]        i_codeword,     // 8-bit input
    input  wire              i_valid,       // (gem) alert new codeword valid
    output reg signed [7:0]  o_sample,     // Sample BPSK output
    output reg               o_valid,     // alert output valied
    output reg               o_done      // 1 = done, can get new codeword
);

    reg        busy;                // 0 = module free, 1 = cooking
    reg [7:0]  codeword_reg; 
    reg [5:0]  sample_index;       // count 0-63, 2^6 = 64

    always @(posedge i_clk) begin   //reset data
        if (!i_rst_n) begin
            busy         <= 1'b0;
            codeword_reg <= 8'b0;
            sample_index <= 6'd0;
            o_sample     <= 8'sd0;
            o_valid      <= 1'b0;
            o_done       <= 1'b0;
        end else begin             //default setup
            o_valid <= 1'b0;
            o_done  <= 1'b0;

            if (!busy) begin
                if (i_valid) begin
                    codeword_reg <= i_codeword;
                    sample_index <= 6'd0;
                    busy         <= 1'b1;
                end
            end else begin
                // Select codeword bit, MSB-first 
                o_sample <= codeword_reg[3'd7 - sample_index[5:3]]   // reverse 7-0 -> 0-7  and convert bit 0/1 to 8x-127/8x127
                            ? -8'sd127 : 8'sd127;                    // sign decimal
                o_valid <= 1'b1;

                if (sample_index == 6'd63) begin
                    o_done       <= 1'b1;
                    busy         <= 1'b0;
                    sample_index <= 6'd0;
                end else begin
                    sample_index <= sample_index + 6'd1;
                end
            end
        end
    end
endmodule
