`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/03/2026 02:58:27 AM
// Design Name: Nguyen Tri Tue 
// Module Name: sobel_3x3
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
// Sobel 3x3, latency 1 cycle. Gx/Gy in [-1020, 1020] -> 11-bit signed is enough.
module sobel_3x3 (
    input  wire                i_clk,
    input  wire                i_rst,     // sync, active-high
    input  wire                i_window_valid,
    input  wire [7:0]          i_p00, i_p01, i_p02,
    input  wire [7:0]          i_p10,        i_p12,   // p11 not used
    input  wire [7:0]          i_p20, i_p21, i_p22,

    output reg signed [10:0]   o_gx,
    output reg signed [10:0]   o_gy,
    output reg                 o_sobel_result_valid
);

    wire signed [10:0] w_gx_comb =
          -$signed({3'b000, i_p00}) + $signed({3'b000, i_p02})
        - ($signed({3'b000, i_p10}) <<< 1) + ($signed({3'b000, i_p12}) <<< 1)
        -  $signed({3'b000, i_p20}) + $signed({3'b000, i_p22});

    wire signed [10:0] w_gy_comb =
          -$signed({3'b000, i_p00}) - ($signed({3'b000, i_p01}) <<< 1) - $signed({3'b000, i_p02})
        +  $signed({3'b000, i_p20}) + ($signed({3'b000, i_p21}) <<< 1) + $signed({3'b000, i_p22});

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_gx                 <= 11'sd0;
            o_gy                 <= 11'sd0;
            o_sobel_result_valid <= 1'b0;
        end
        else begin
            o_gx                 <= i_window_valid ? w_gx_comb : 11'sd0;
            o_gy                 <= i_window_valid ? w_gy_comb : 11'sd0;
            o_sobel_result_valid <= i_window_valid;
        end
    end

endmodule
`default_nettype wire