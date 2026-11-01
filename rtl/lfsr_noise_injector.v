module lfsr_noise_injector (
    input wire i_clk,
    input wire i_rst_n,                     // 0-> reset, 1->active 

    input wire signed [7:0] i_sample,       // 
    input wire i_valid,                     // check i_sample valid or invalid
    input wire i_done,                      // = 1 when 64 sample done 
    input wire [2:0] i_noise_level,         // noise level from 0->7 = 2^3 = 8 

    output reg signed [7:0] o_sample,       // sample output after + noise 
    output reg o_valid,                     // sample output valid or not invalid 
    output reg o_done                      // the final sample of frame
);

 reg [7:0] noise_lfsr;                   // cre a 8 bit register to storage current LFSR status

    wire feedback;                          // this is a bit which calculated with XOR (0 or 1)
    wire [7:0]  next_lfsr;                  // next status is calculated to use in next update 

assign feedback = 
    noise_lfsr[7] ^
    noise_lfsr[5] ^
    noise_lfsr[4] ^
    noise_lfsr[3];

assign next_lfsr = {noise_lfsr[6:0], feedback};

reg signed [8:0] noise_amplitude;           

always @(*) begin
    case (i_noise_level)                   //choose noise level from 4->64 (still dk - or +)
        3'd0: noise_amplitude = 9'sd0;
        3'd1: noise_amplitude = 9'sd4;
        3'd2: noise_amplitude = 9'sd8;
        3'd3: noise_amplitude = 9'sd16;
        3'd4: noise_amplitude = 9'sd24;
        3'd5: noise_amplitude = 9'sd32;
        3'd6: noise_amplitude = 9'sd48;
        3'd7: noise_amplitude = 9'sd64;
        default: noise_amplitude = 9'sd0;
    endcase         
    
end

wire signed [8:0] signed_noise;        

assign signed_noise = noise_lfsr[7] ? -noise_amplitude : noise_amplitude; // if noise_lfsr[7]= 1 -> -noise-amplitude 
                                                                          // otherwise = 0 -> +noise_amplitude

wire signed [9:0] sample_extended;          // version 10 bit of i_sample                       -512<x<211
wire signed [9:0] noise_extended;           // version 10 bit of signed_noise
wire signed [9:0] raw_sum;                  // sum of i_sample(10b) and signed_noise(10b)

assign sample_extended = {{2{i_sample[7]}}, i_sample};
assign noise_extended  = {{1{signed_noise[8]}}, signed_noise};

assign raw_sum = sample_extended + noise_extended;

reg signed [7:0] saturated_sample;          // storage output after limit (from 10bit to 8bit)

always @(*) begin
    if (raw_sum > 10'sd127)                 
        saturated_sample = 8'sd127;         // if raw_sum > 127 -> back to 127 
    else if (raw_sum < -10'sd128)   
        saturated_sample = -8'sd128;        // if raw_sum < 128 -> back to 128 
    else
        saturated_sample = raw_sum[7:0];
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        noise_lfsr <= 8'h01;        // noise_lfsr = 0000 0001
        o_sample   <= 8'sd0;        
        o_valid    <= 1'b0;
        o_done     <= 1'b0;
end
else begin
    o_valid <= 1'b0;
    o_done  <= 1'b0;

    if (i_valid) begin
        o_sample <= saturated_sample;
        o_valid  <= 1'b1;
        o_done   <= i_done;

        if (next_lfsr == 8'h00)
            noise_lfsr <= 8'h01;
        else 
            noise_lfsr <= next_lfsr;
     end
   end
end 

endmodule 
