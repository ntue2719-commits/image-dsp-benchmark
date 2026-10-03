`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/03/2026
// Design Name: Nguyen Tri Tue
// Module Name: gradient_mag
// Project Name: 
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
// |Gx| + |Gy|, combinational. Max 2040 -> 12-bit unsigned.
module gradient_mag (
    input  wire               i_sobel_result_valid,
    input  wire signed [10:0] i_gx,
    input  wire signed [10:0] i_gy,

    output wire [11:0]        o_mag,
    output wire               o_grad_result_valid
);

    wire [10:0] w_abs_gx = i_gx[10] ? (~i_gx + 11'd1) : i_gx;
    wire [10:0] w_abs_gy = i_gy[10] ? (~i_gy + 11'd1) : i_gy;

    assign o_mag               = i_sobel_result_valid ? ({1'b0, w_abs_gx} + {1'b0, w_abs_gy}) : 12'd0;
    assign o_grad_result_valid = i_sobel_result_valid;

endmodule
`default_nettype wire