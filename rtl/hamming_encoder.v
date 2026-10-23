`default_nettype none
module hamming_encoder (
    input wire          i_clk,
    input wire          i_rst_n,
    input wire [3:0]    i_data,
    input wire          i_start,

    output reg [7:0]    o_codeword,
    output reg          o_valid
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


//Internal register
reg [3:0] r_data;
reg       r_pending;


//Parity generation
wire w_d0 = r_data[0];
wire w_d1 = r_data[1];
wire w_d2 = r_data[2];
wire w_d3 = r_data[3];

wire w_p1 = w_d0 ^ w_d1 ^ w_d3;
wire w_p2 = w_d0 ^ w_d2 ^ w_d3;
wire w_p3 = w_d1 ^ w_d2 ^ w_d3;

wire w_p0 = w_p1 ^ w_p2 ^ w_d0 ^ w_p3 ^ w_d1 ^ w_d2 ^ w_d3;

wire [7:0] w_codeword = {w_p0, w_d3, w_d2, w_d1, w_p3, w_d0, w_p2, w_p1};

always @ (posedge i_clk) begin
    if(!i_rst_n) begin
        r_data <= 4'd0;
        r_pending <= 1'b0;
        o_codeword <= 8'd0;
        o_valid <= 1'b0;
    end
    else begin

        //Default: output valid pulse is one-clock wide
        o_valid <= 1'b0;

        if(r_pending) begin
            o_codeword <= w_codeword;
            o_valid <= 1'b1;
            r_pending <= 1'b0;
        end
        else if (i_start) begin
            //accept request only when idle
            r_data <= i_data;
            r_pending <= 1'b1;
        end
    end
end

endmodule 
`default_nettype wire


