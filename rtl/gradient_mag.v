module gradient_mag (
    input wire i_sobel_result_valid,
    input wire [10:0] i_gx,
    input wire [10:0] i_gy,
    output reg [11:0] o_mag,
    output reg o_grad_result_valid
);

wire [10:0] w_abs_gx, w_abs_gy;
    assign abs_gx = i_gx[10] ? -i_gx : i_gx;
    assign abs_gy = i_gy[10] ? -i_gy : i_gy;
always @(*) begin
    if(i_sobel_result_valid) begin
        o_mag = w_abs_gx + w_abs_gy;
        o_grad_result_valid = 1'b1;
    end
    else begin
        o_mag = 12'h0;
        o_grad_result_valid = 1'b0;
    end
end
endmodule

