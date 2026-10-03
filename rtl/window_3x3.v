`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/28/2026 04:59:43 PM
// Design Name: 
// Module Name: window_3x3
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
//////////////////////////////////////////////////////////////////////////////
`default_nettype none

module window_3x3 (
    input  wire       i_clk,
    input  wire       i_rst,
    input  wire       i_en,

    input  wire [7:0] i_row0,
    input  wire [7:0] i_row1,
    input  wire [7:0] i_row2,

    output wire [7:0] o_p00,
    output wire [7:0] o_p01,
    output wire [7:0] o_p02,

    output wire [7:0] o_p10,
    output wire [7:0] o_p11,
    output wire [7:0] o_p12,

    output wire [7:0] o_p20,
    output wire [7:0] o_p21,
    output wire [7:0] o_p22
);

    // Two previous columns for each of the three rows.
    reg [7:0] p00_reg, p01_reg;
    reg [7:0] p10_reg, p11_reg;
    reg [7:0] p20_reg, p21_reg;

    always @(posedge i_clk) begin
        if (i_rst) begin
            p00_reg <= 8'd0;
            p01_reg <= 8'd0;

            p10_reg <= 8'd0;
            p11_reg <= 8'd0;

            p20_reg <= 8'd0;
            p21_reg <= 8'd0;
        end
        else if (i_en) begin
            // Top row
            p00_reg <= p01_reg;
            p01_reg <= i_row0;

            // Middle row
            p10_reg <= p11_reg;
            p11_reg <= i_row1;

            // Bottom row
            p20_reg <= p21_reg;
            p21_reg <= i_row2;
        end
    end

    // Window:
    //
    // p00 p01 p02
    // p10 p11 p12
    // p20 p21 p22
    //
    // i_row* is the newest/rightmost column.

    assign o_p00 = p00_reg;
    assign o_p01 = p01_reg;
    assign o_p02 = i_row0;

    assign o_p10 = p10_reg;
    assign o_p11 = p11_reg;
    assign o_p12 = i_row1;

    assign o_p20 = p20_reg;
    assign o_p21 = p21_reg;
    assign o_p22 = i_row2;

endmodule

`default_nettype wire