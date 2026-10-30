`default_nettype none
module bit_flip_channel (
    input wire          i_clk,
    input wire          i_rst_n,
    input wire [7:0]    i_codeword,
    input wire          i_valid,
    input wire [1:0]    i_err_mode,

    output reg [7:0]    o_codeword,
    output reg          o_valid
);

//LFSR: x^8 + x^6 + x^5 + x^4 + 1, seed = 8'hA5
reg [7:0] r_lfsr;
// Modulo-2 XOR feedback from polynomial taps [7, 5, 4, 3]
wire      w_feedback  = r_lfsr[7] ^ r_lfsr[5] ^ r_lfsr[4] ^ r_lfsr[3];
// Shift left 1 bit and insert feedback into LSB; reload seed if 0 to prevent zero-lockup
wire [7:0] w_next_lfsr = ({r_lfsr[6:0], w_feedback} == 8'h00) ? 8'hA5 : {r_lfsr[6:0], w_feedback};

// Error bit positions: pos1 from lower 3 bits, pos2 from middle 3 bits
wire [2:0] w_pos1 = r_lfsr[2:0];
// Collision resolution: if pos1 == pos2, increment pos2 by 1 (mod 8) to ensure 2 distinct bit flips
wire [2:0] w_pos2 = (r_lfsr[2:0] == r_lfsr[5:3]) ? (r_lfsr[5:3] + 3'd1) : r_lfsr[5:3];

// Error mask: (8'h01 << pos) generates a 1-hot mask at target bit for XOR flipping
// 00=none, 01=single bit (pos1), 10=double bit (pos1, pos2)
wire [7:0] w_flip_mask = (i_err_mode == 2'b01) ? (8'h01 << w_pos1) :
                         (i_err_mode == 2'b10) ? ((8'h01 << w_pos1) | (8'h01 << w_pos2)) : 8'h00;

always @ (posedge i_clk) begin
    if(!i_rst_n) begin
        r_lfsr     <= 8'hA5;
        o_codeword <= 8'h00;
        o_valid    <= 1'b0;
    end
    else begin
        o_valid <= i_valid;
        if(i_valid) begin
            o_codeword <= i_codeword ^ w_flip_mask;
            r_lfsr     <= w_next_lfsr;
        end
        else begin
            o_codeword <= 8'h00;
        end
    end
end

endmodule
`default_nettype wire
