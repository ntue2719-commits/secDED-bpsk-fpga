
`timescale 1ns / 1ps
`default_nettype none

module uart_rx #(
    parameter integer CLKS_PER_BIT = 434    // 1 bit exist in 434 cycle clock of FPGA 
)(
    input wire i_clk,                       // clk = 50Mhz
    input wire i_rst_n,                     // 0-> reset, 1->active
    input wire i_rx,                        // receive bit 0 or 1 

    output reg [7:0] o_data,                // data byte after uart_rx receive enough 8 bit and check valid stop bit
    output reg o_valid                      // announce receive 1 byte (8bit) successfully = 1 
);

    localparam integer HALF_BIT_CLKS = CLKS_PER_BIT / 2; 

    localparam [2:0] IDLE  = 3'd0;          // FSM = 000, waiting status
    localparam [2:0] START = 3'd1;          // FSM = 001, check start bit of UART
    localparam [2:0] DATA  = 3'd2;          // FSM = 010, receive each bit of byte 
    localparam [2:0] STOP  = 3'd3;          // FSM = 011, check stop bit 

    reg [2:0] r_state;        // register storage current status of FSM
    reg [8:0] r_clk_count;    // count the cycle clock 
    reg [2:0] r_bit_index;    // register for uart_rx to know đang nhận bit dữ liệu thứ mấy (0->7)
                              // 0 = 000, 1 = 001, 2 = 010, 3 = 011, 4 = 100, 5 = 101, 6 = 110, 7 = 111
    reg [7:0] r_data;         // temporarily storage bit which received from UART

    always @(posedge i_clk) begin
        if (!i_rst_n) begin             // if i_rst_n = 0 -> uart_rx reset synchronize
            r_state     <= IDLE;        // r_state back to IDLE(waiting)
            r_clk_count <= 9'd0;        // clk_count = 0
            r_bit_index <= 3'd0;        // place r_bit_index to position 0 (D0)
            r_data      <= 8'd0;        // delete data of register 
            o_data      <= 8'd0;        // delete byte output 
            o_valid     <= 1'b0;        // set valid = 0 -> invalid 
        end
        else begin                      // active when i_rst_n = 1 
            o_valid <= 1'b0;            // default = 0 , only become 1 when receive enough 1 byte and check valid stop bit in 1 cylce clock

            case (r_state)              //decide to excute IDLE or START or DATA or STOP
                IDLE: begin
                    r_clk_count <= 9'd0;     // take clk_count back to 0
                    r_bit_index <= 3'd0;     // place r_bit_index to position 0 (D0)

                    if (!i_rx) begin        // if i_rx = 0 (start)
                        r_state <= START;
                    end
                end

                START: begin
                    if (r_clk_count == HALF_BIT_CLKS - 1) begin   // r_clk_count = 216 
                        r_clk_count <= 9'd0;                      // take clk_count back to 0 

                        if (!i_rx) begin
                            r_state <= DATA;
                        end
                        else begin
                            r_state <= IDLE;
                        end
                    end
                    else begin
                        r_clk_count <= r_clk_count + 1'b1;         // r_clk_count + 1 until = 216 
                    end
                end

                DATA: begin
                    if (r_clk_count == CLKS_PER_BIT - 1) begin    // r_clk_count = 434 ,start take a bit data 
                        r_clk_count <= 9'd0;                      // reset clk_count back to 0 , and contiune count more 434 cycle 
                        r_data[r_bit_index] <= i_rx;       // storage bit in position(0->7) of data register

                        if (r_bit_index == 3'd7) begin      // position 7 received bit -> enough 8 bit 
                            r_bit_index <= 3'd0;            // restart to 0 to repair for next byte 
                            r_state <= STOP;                
                        end
                        else begin
                            r_bit_index <= r_bit_index + 1'b1;  // count for bit_dex from D0->D7 
                        end
                    end
                    else begin
                        r_clk_count <= r_clk_count + 1'b1;     //count until clk_count = 433
                    end
                end

                STOP: begin
                    if (r_clk_count == CLKS_PER_BIT - 1) begin      //check clk_count = 433 or not
                        r_clk_count <= 9'd0;                        // if = 433 -> reset to 0 

                        if (i_rx) begin           // if i_rx = 1
                            o_data <= r_data;     // store data in r_data to o_data
                            o_valid <= 1'b1;      // valid
                        end

                        r_state <= IDLE;        // back to the IDLE after valid 
                    end
                    else begin
                        r_clk_count <= r_clk_count + 1'b1;
                    end
                end

                default: begin
                    r_state <= IDLE;
                    r_clk_count <= 9'd0;
                    r_bit_index <= 3'd0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
