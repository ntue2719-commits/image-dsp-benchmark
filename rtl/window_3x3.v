`timescale 1ns / 1ps

module window_3x3 (
    input  wire       clk,
    input  wire       rst,
    input  wire       en,
    input  wire [7:0] row0_in,
    input  wire [7:0] row1_in,
    input  wire [7:0] row2_in,
    
    output wire [7:0] p00,
    output wire [7:0] p01,
    output wire [7:0] p02,
    
    output wire [7:0] p10,
    output wire [7:0] p11,
    output wire [7:0] p12,
    
    output wire [7:0] p20,
    output wire [7:0] p21,
    output wire [7:0] p22
);

    //-------------------------------------------------------------------------
    // Khai báo thanh ghi (Registers) lưu trữ 2 cột dữ liệu cũ (Delay ngang)
    //-------------------------------------------------------------------------
    reg [7:0] p00_reg, p01_reg;
    reg [7:0] p10_reg, p11_reg;
    reg [7:0] p20_reg, p21_reg;

    //-------------------------------------------------------------------------
    // Logic dịch dữ liệu (Shift Register)
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            p00_reg <= 8'd0;
            p01_reg <= 8'd0;
            p10_reg <= 8'd0;
            p11_reg <= 8'd0;
            p20_reg <= 8'd0;
            p21_reg <= 8'd0;
        end 
        else if (en) begin
            // Dịch cột dọc
            p00_reg <= p01_reg;
            p01_reg <= row0_in;
            
            p10_reg <= p11_reg;
            p11_reg <= row1_in;
            
            p20_reg <= p21_reg;
            p21_reg <= row2_in;
        end
    end

    //-------------------------------------------------------------------------
    // Combinational Output (Đúng chuẩn 0-cycle latency theo Spec)
    //-------------------------------------------------------------------------
    // Cột trái (cũ nhất)
    assign p00 = p00_reg;
    assign p10 = p10_reg;
    assign p20 = p20_reg;
    
    // Cột giữa
    assign p01 = p01_reg;
    assign p11 = p11_reg;
    assign p21 = p21_reg;
    
    // Cột phải (mới nhất - lấy trực tiếp từ input = 0 cycle latency)
    assign p02 = row0_in;
    assign p12 = row1_in;
    assign p22 = row2_in;

endmodule
