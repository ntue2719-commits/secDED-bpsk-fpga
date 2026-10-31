`timescale 1ns / 1ps
`default_nettype none    // not cre auto wire 

module line_buffer #(
    parameter IMAGE_WIDTH = 512,    //cr
    parameter COORD_W = 12          // representing x and y coordinates , from 0 to 2^12 = 4095
)(
    input wire                   i_clk,
    input wire                   i_rst,             // if 1 -> reset, 0 -> active nor
    input wire                   i_valid,           // if 1 -> valid, 0 -> invalid
    input wire [7:0]             i_pixel,           
    input wire [COORD_W-1:0]     i_x,               // col
    input wire [COORD_W-1:0]     i_y,               // line

    output reg                 o_valid,
    output reg [7:0]           o_top,
    output reg [7:0]           o_mid,
    output reg [7:0]           o_bot,
    output reg [COORD_W-1:0]   o_x,
    output reg [COORD_W-1:0]   o_y
);


    function integer clog2;              // function to count bit width image
    input integer value;
    integer v;
    begin
        v = value - 1;
        clog2 = 0;                      // set the return value 
        while (v > 0) begin
            clog2 = clog2 + 1;
            v = v >> 1;                 // bit shift 
        end
    end
endfunction

localparam ADDR_W = clog2(IMAGE_WIDTH); 

reg [7:0] line1 [0:IMAGE_WIDTH - 1];        // storage 512 element of line 1
reg [7:0] line2 [0:IMAGE_WIDTH - 1];        // storage 512 element of line 2 

reg [ADDR_W - 1:0] col;

 always @ (posedge i_clk) begin
        if(i_rst) begin
            col <= {ADDR_W{1'b0}};          // set col return to 0 
            
            o_top <= 8'd0;                  // 00000000
            o_mid <= 8'd0;
            o_bot <= 8'd0;
            
            o_x <= {COORD_W{1'b0}};         //000000000000
            o_y <= {COORD_W{1'b0}};
            
            o_valid <= 1'b0;                // data output is invalid 
        end
        else begin
            o_valid <= i_valid;             
            if(i_valid) begin
                o_top <= line2[col];              // storage pixel at line 2 col n
                o_mid <= line1[col];              // storage pixel at line 1 col n
                o_bot <= i_pixel;                 // storage pixel at current 
                
                o_x <= i_x;
                o_y <= i_y;
                
                line2[col] <= line1[col];           // take the pixel at line 1 to line 2 to update 
                line1[col] <= i_pixel;              // take the pixel at line curent to line 1 to update 
                
                if(col == IMAGE_WIDTH -1)              // if col == 511 (end)
                    col <= {ADDR_W{1'b0}};              // back col to 0 and continue 
                else
                    col <= col + 1;                    
            end
        end
    end   
endmodule
`default_nettype wire