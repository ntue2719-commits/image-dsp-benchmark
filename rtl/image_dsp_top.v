`default_nettype none

module image_dsp_top    #(
    parameter IMAGE_WIDTH = 512,
    parameter IMAGE_HEIGHT = 512,
    parameter THRESHOLD = 100,
    parameter COORD_W = 12
) (
    input wire          i_clk,
    input wire          i_rst,
    input wire          i_valid,
    input wire [7:0]    i_pixel,

    output wire         o_valid,
    output wire [7:0]   o_pixel,
    output wire [COORD_W -1 : 0] o_x,
    output wire [COORD_W -1 : 0] o_y,
    output wire [11:0]           o_mag
);

//Source coordinate generator (only place with a raster counter)

reg [COORD_W-1: 0] in_x, in_y;

always @(posedge i_clk) begin
    if(i_rst) begin
        in_x <= {COORD_W{1'b0}};
        in_y <= {COORD_W{1'b0}};
    end
    else if (i_valid) begin
        if(in_x == IMAGE_WIDTH -1 ) begin
            in_x <= {COORD_W{1'b0}};
            if(in_y == IMAGE_HEIGHT -1 ) 
                in_y <= {COORD_W{1'b0}};
            else 
                in_y <= in_y + 1'b1;
        end
        else
            in_x <= in_x + 1'b1;
    end
end

//Stage 1: 3x3 median on the full WxH stream -> valid centre [1...W-2]x[1...H-2]

wire lb1_valid;
wire [7:0] lb1_top, lb1_mid, lb1_bot;
wire[COORD_W-1:0] lb1_x, lb1_y;

line_buffer #(
    .IMAGE_WIDTH(IMAGE_WIDTH),
    .COORD_W(COORD_W)
) u_lb1 (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_valid(i_valid),
    .i_pixel(i_pixel), .i_x(in_x), .i_y(in_y),
    .o_valid(lb1_valid),
    .o_top(lb1_top), .o_mid(lb1_mid), .o_bot(lb1_bot),
    .o_x(lb1_x), .o_y(lb1_y)
);

wire [7:0]  w1_p00, w1_p01, w1_p02;
wire [7:0]  w1_p10, w1_p11, w1_p12;
wire [7:0]  w1_p20, w1_p21, w1_p22;

window_3x3 u_win1 (
    .i_clk(i_clk), .i_rst(i_rst), .i_en(lb1_valid),
    .i_row0(lb1_top), .i_row1(lb1_mid), .i_row2(lb1_bot),
    .o_p00(w1_p00), .o_p01(w1_p01), .o_p02(w1_p02),
    .o_p10(w1_p10), .o_p11(w1_p11), .o_p12(w1_p12),
    .o_p20(w1_p20), .o_p21(w1_p21), .o_p22(w1_p22)
);


//newest pixel (x,y) -> window centre (x-1, y-1); need x>=2, y>=2 (no wrap, rows filled)

wire w1_valid = lb1_valid && (lb1_x >= 2) && (lb1_y >= 2);

wire [7:0] med_pixel;
wire       med_valid;

median_3x3 u_median (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_window_valid(w1_valid),
    .i_p00(w1_p00), .i_p01(w1_p01), .i_p02(w1_p02),
    .i_p10(w1_p10), .i_p11(w1_p11), .i_p12(w1_p12),
    .i_p20(w1_p20), .i_p21(w1_p21), .i_p22(w1_p22),
    .o_median(med_pixel), .o_median_valid(med_valid)
);

//coordinates follow the median (1-cycle latency, same as median register)

reg [COORD_W-1:0] med_x, med_y;

always @ (posedge i_clk) begin
    if(i_rst) begin
        med_x <= {COORD_W{1'b0}};
        med_y <= {COORD_W{1'b0}};
    end
    else begin
        med_x <= lb1_x -1'b1;
        med_y <= lb1_y - 1'b1;
    end
end


//Stage 2: sobel on the median stream. Only valid median pixel enter, so this stream has IMAGE_WIDTH-2 pixels per rows.

wire        lb2_valid;
wire [7:0]  lb2_top, lb2_mid, lb2_bot;
wire [COORD_W -1 :0] lb2_x, lb2_y;

line_buffer #(.IMAGE_WIDTH(IMAGE_WIDTH - 2), .COORD_W(COORD_W)) u_lb2 (
        .i_clk(i_clk), .i_rst(i_rst),
        .i_valid(med_valid), .i_pixel(med_pixel), .i_x(med_x), .i_y(med_y),
        .o_valid(lb2_valid), .o_top(lb2_top), .o_mid(lb2_mid), .o_bot(lb2_bot),
        .o_x(lb2_x), .o_y(lb2_y)
    );

wire [7:0] w2_p00, w2_p01, w2_p02, w2_p10, w2_p11, w2_p12, w2_p20, w2_p21, w2_p22;

    window_3x3 u_win2 (
        .i_clk(i_clk), .i_rst(i_rst), .i_en(lb2_valid),
        .i_row0(lb2_top), .i_row1(lb2_mid), .i_row2(lb2_bot),
        .o_p00(w2_p00), .o_p01(w2_p01), .o_p02(w2_p02),
        .o_p10(w2_p10), .o_p11(w2_p11), .o_p12(w2_p12),
        .o_p20(w2_p20), .o_p21(w2_p21), .o_p22(w2_p22)
    );

// median stream starts at image coord 1 -> first full window when newest x>=3, y>=3
    wire w2_valid = lb2_valid && (lb2_x >= 3) && (lb2_y >= 3);

    wire signed [10:0] sob_gx, sob_gy;
    wire               sob_valid;

    sobel_3x3 u_sobel (
        .i_clk(i_clk), .i_rst(i_rst), .i_window_valid(w2_valid),
        .i_p00(w2_p00), .i_p01(w2_p01), .i_p02(w2_p02),
        .i_p10(w2_p10),                 .i_p12(w2_p12),
        .i_p20(w2_p20), .i_p21(w2_p21), .i_p22(w2_p22),
        .o_gx(sob_gx), .o_gy(sob_gy), .o_sobel_result_valid(sob_valid)
    );

    reg [COORD_W-1:0] sob_x, sob_y;
    always @(posedge i_clk) begin
        if (i_rst) begin
            sob_x <= {COORD_W{1'b0}};
            sob_y <= {COORD_W{1'b0}};
        end
        else begin
            sob_x <= lb2_x - 1'b1;
            sob_y <= lb2_y - 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Magnitude + threshold (combinational, aligned with the Sobel register)
    // ------------------------------------------------------------------
    wire grad_valid;

    gradient_mag u_grad (
        .i_sobel_result_valid(sob_valid), .i_gx(sob_gx), .i_gy(sob_gy),
        .o_mag(o_mag), .o_grad_result_valid(grad_valid)
    );

    threshold #(.THRESHOLD(THRESHOLD)) u_thr (
        .i_mag(o_mag), .i_grad_result_valid(grad_valid),
        .o_pixel_out(o_pixel), .o_pixel_valid_out(o_valid)
    );

    assign o_x = sob_x;
    assign o_y = sob_y;

endmodule
`default_nettype wire
