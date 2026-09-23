module sobel_3x3 (
    input wire                  i_clk,
    input wire                  i_rstn,
    input wire                  i_window_valid,
    input wire [7:0]            i_p00, i_p01, i_p02,
    input wire [7:0]            i_p10,        i_p12, //not use p11
    input wire [7:0]            i_p20, i_p21, i_p22,
    output reg signed [10:0]    o_Gx,
    output reg signed  [10:0]   o_Gy,
    output reg                  o_sobel_result_valid
);
// Sobel kernel coefficients:
wire signed [10:0] w_gx_comb;
    // Gx = (-1*p00) + (0*p01) + (1*p02)
    //    + (-2*p10) + (0*p11) + (2*p12)
    //    + (-1*p20) + (0*p21) + (1*p22)
wire signed [10:0] w_gy_comb;
    // Gy = (-1*p00) + (-2*p01) + (-1*p02)
    //    + (0*p10)  + (0*p11)  + (0*p12)
    //    + (1*p20)  + (2*p21)  + (1*p22)


//arithmetic shift left (<<<), 
assign w_gx_comb = -$signed({3'b0, i_p00}) + $signed({3'b0, i_p02})
                - ($signed({3'b0, i_p10}) <<< 1) + ($signed({3'b0, i_p12}) <<< 1)
                - $signed({3'b0, i_p20}) + $signed({3'b0, i_p22});

assign w_gy_comb = -$signed({3'b0, i_p00}) - ($signed({3'b0, i_p01}) <<< 1) - $signed({3'b0, i_p02})
                     + $signed({3'b0, i_p20}) + ($signed({3'b0, i_p21}) <<< 1) + $signed({3'b0, i_p22});


always @ (posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin
        o_Gx <= 11'h0;
        o_Gy <= 11'h0;
        o_sobel_result_valid <= 1'h0;
    end
    else begin
        o_Gx <= i_window_valid ? w_gx_comb : 11'h0;
        o_Gy <= i_window_valid ? w_gy_comb : 11'h0;
        o_sobel_result_valid <= i_window_valid;
    end
end

endmodule