module bpsk_demodulator (
    input  wire                    i_clk,
    input  wire                    i_rst_n,

    input  wire signed [7:0]       i_sample,
    input  wire                    i_valid,
    input  wire                    i_done,

    output reg  [7:0]              o_codeword,
    output reg                     o_valid
);

    // Internal registers
    reg [2:0] bit_index; //Use to track the bit currently being recovered
    reg [2:0] sample_index; //Used to track which sample of the current bit is being processed

    reg signed [10:0] demod_acc; //Accumulator for the sum of samples for the current bit
    reg signed [10:0] sample_ext; //Sign-extended version of the current sample to match the accumulator's width
    reg signed [10:0] acc_next; //Next value of the accumulator after adding the current sample

    // Sign extension and accumulation
    always @(*) begin
        sample_ext = {{3{i_sample[7]}}, i_sample}; // Sign-extend the 8-bit sample to 11 bits
        acc_next   = demod_acc + sample_ext; // Calculate the next accumulator value
    end

    // BPSK demodulation
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            bit_index    <= 3'd0;
            sample_index <= 3'd0;
            demod_acc    <= 11'sd0;
            o_codeword   <= 8'd0;
            o_valid      <= 1'b0;
        end
        else begin
            // Default: one-cycle valid pulse
            o_valid <= 1'b0;

            if (i_valid) begin

                // If done arrives before sample 63, discard the incomplete frame.
                if (i_done && !((bit_index == 3'd7) && (sample_index == 3'd7))) begin
                    bit_index    <= 3'd0;
                    sample_index <= 3'd0;
                    demod_acc    <= 11'sd0;
                end

                // Collect 8 samples for one bit
                else if (sample_index == 3'd7) begin

                    // Decision using the sum including
                    // the current (eighth) sample
                    if (acc_next >= 11'sd0)
                        o_codeword[7 - bit_index] <= 1'b0;
                    else
                        o_codeword[7 - bit_index] <= 1'b1;

                    // Start accumulating the next bit
                    demod_acc    <= 11'sd0;
                    sample_index <= 3'd0;

                    // Check whether all 8 bits are done
                    if (bit_index == 3'd7) begin
                        bit_index <= 3'd0;

                        // A complete codeword is valid only
                        // when done marks the final sample.
                        if (i_done)
                            o_valid <= 1'b1;
                    end
                    else begin
                        bit_index <= bit_index + 1'b1;
                    end

                end
                else begin
                    // Accumulate samples 1 through 7
                    demod_acc    <= acc_next;
                    sample_index <= sample_index + 1'b1;
                end
            end

            // done implies valid in the normal interface.
            // If not, discard any incomplete frame.
            else if (i_done) begin
                bit_index    <= 3'd0;
                sample_index <= 3'd0;
                demod_acc    <= 11'sd0;
            end
        end
    end
endmodule