`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/28/2026 09:14:41 PM
// Design Name:
// Module Name: line_buffer
// Project Name: Image DSP
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`default_nettype none

module line_buffer #(
    parameter IMAGE_WIDTH = 512,
    parameter COORD_W =12
)(
    input wire                 i_clk,
    input wire                 i_rst,
    input wire                 i_valid,
    input wire [7:0]           i_pixel,
    input wire [COORD_W -1 :0] i_x,
    input wire [COORD_W -1 :0] i_y,
    
    output reg                 o_valid,
    output reg [7:0]           o_top,
    output reg [7:0]           o_mid,
    output reg [7:0]           o_bot,
    output reg [COORD_W -1 :0] o_x,
    output reg [COORD_W -1 :0] o_y 
    );
    
    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value -1;
            clog2 = 0;
            while (v>0) begin
                clog2= clog2 +1;
                v = v >> 1;
            end        
        end    
    endfunction
    
    localparam ADDR_W = clog2(IMAGE_WIDTH);
    
    reg [7:0] line1 [0: IMAGE_WIDTH -1];
    reg [7:0] line2 [0: IMAGE_WIDTH -1];
    
    reg [ADDR_W - 1:0] col;
    
    always @ (posedge i_clk) begin
        if(i_rst) begin
            col <= {ADDR_W{1'b0}};
            
            o_top <= 8'd0;
            o_mid <= 8'd0;
            o_bot <= 8'd0;
            
            o_x <= {COORD_W{1'b0}}; 
            o_y <= {COORD_W{1'b0}};
            
            o_valid <= 1'b0;
        end
        else begin
            o_valid <= i_valid;
            if(i_valid) begin
                o_top <= line2[col];
                o_mid <= line1[col];
                o_bot <= i_pixel;
                
                o_x <= i_x;
                o_y <= i_y;
                
                line2[col] <= line1[col];
                line1[col] <= i_pixel;
                
                if(col == IMAGE_WIDTH -1)
                    col <= {ADDR_W{1'b0}};
                else
                    col <= col + 1;
            end
        end
    end   
endmodule
`default_nettype wire