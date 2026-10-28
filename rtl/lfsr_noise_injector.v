module lfsr_noise_injector (
    input  wire              i_clk,
    input  wire              i_rst_n,

    input  wire signed [7:0] i_sample,
    input  wire              i_valid,
    input  wire              i_done,
    input  wire        [2:0] i_noise_level,

    output reg  signed [7:0] o_sample,
    output reg               o_valid,
    output reg               o_done
);

    reg [7:0] noise_lfsr;

    wire feedback;
    wire [7:0] next_lfsr;

    assign feedback =
        noise_lfsr[7] ^
        noise_lfsr[5] ^
        noise_lfsr[4] ^
        noise_lfsr[3];

    assign next_lfsr = {noise_lfsr[6:0], feedback};

    reg signed [8:0] noise_amplitude;

    always @(*) begin
        case (i_noise_level)
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

    assign signed_noise =
        noise_lfsr[7] ? -noise_amplitude : noise_amplitude;

    wire signed [9:0] sample_extended;
    wire signed [9:0] noise_extended;
    wire signed [9:0] raw_sum;

    assign sample_extended = {{2{i_sample[7]}}, i_sample};
    assign noise_extended  = {{1{signed_noise[8]}}, signed_noise};

    assign raw_sum = sample_extended + noise_extended;

    reg signed [7:0] saturated_sample;

    always @(*) begin
        if (raw_sum > 10'sd127)
            saturated_sample = 8'sd127;
        else if (raw_sum < -10'sd128)
            saturated_sample = -8'sd128;
        else
            saturated_sample = raw_sum[7:0];
    end

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            noise_lfsr <= 8'h01;
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