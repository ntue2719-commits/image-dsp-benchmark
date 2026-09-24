module line_buffer #( 
    parameter IMAGE_WIDTH = 512
) ( 
    input clk,
    input rst, // rst = 1 (get module back to start state)
    input pixel_valid,   // identify pixel_in có valid or not  (valid = 1)
    input [7:0] pixel_in,   // 8 bit = 0 -> 255 
    output reg pixel_valid_out, // top_pixel,mid_pixel,_bot_pixel có valid hay ko 
    output reg [7:0] top_pixel,    
    output reg [7:0] middle_pixel,
    output reg [7:0] bottom_pixel
);

reg [7:0] line1 [0:IMAGE_WIDTH - 1];
reg [7:0] line2 [0:IMAGE_WIDTH - 1];

reg [15:0] col;

integer i;

always @(posedge clk) begin
    if (rst) begin            // reset = 1 đưa toàn bộ về trạng thái ban đầu 
    col <= 0;
    pixel_valid_out <= 0;
    top_pixel <= 0;
    middle_pixel <= 0;
    bottom_pixel <= 0;

for ( i = 0; i < IMAGE_WIDTH; i = i + 1) begin
    line1[i] <= 0;
    line2[i] <= 0;
    end
end 
else begin      // rst = 0
    pixel_valid_out <= pixel_valid;         // p_v = 1 --> p_v_o = 1 or p_v = 0 --> p_v_o = 0

    if (pixel_valid) begin    // pixel_valid = 1
    top_pixel <= line2[col];
    middle_pixel <= line1[col];
    bottom_pixel <= pixel_in;

    line2[col] <= line1[col];
    line1[col] <= pixel_in;

    if (col == IMAGE_WIDTH - 1)
        col <= 0;
    else 
        col <= col + 1;
                 end
        end
    end
endmodule 


