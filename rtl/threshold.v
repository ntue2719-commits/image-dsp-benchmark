`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/03/2026
// Design Name: 
// Module Name: threshold
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
module threshold #(
    parameter THRESHOLD = 100
)(
    input  wire [11:0] i_mag,
    input  wire        i_grad_result_valid,

    output wire [7:0]  o_pixel_out,
    output wire        o_pixel_valid_out
);

    assign o_pixel_out       = (i_mag >= THRESHOLD) ? 8'd255 : 8'd0;
    assign o_pixel_valid_out = i_grad_result_valid;

endmodule
`default_nettype wire