module median_3x3(
    input i_clk,
    input i_rst,
    input i_window_valid,

    input [7:0] i_p00,
    input [7:0] i_p01,
    input [7:0] i_p02,

    input [7:0] i_p10,
    input [7:0] i_p11,
    input [7:0] i_p12,

    input [7:0] i_p20,
    input [7:0] i_p21,
    input [7:0] i_p22,

    output reg [7:0] o_median,
    output reg       o_median_valid
);

reg [7:0] s0 [0:8];
reg [7:0] s1 [0:8];
reg [7:0] s2 [0:8];
reg [7:0] s3 [0:8];
reg [7:0] s4 [0:8];
reg [7:0] s5 [0:8];
reg [7:0] s6 [0:8];
reg [7:0] s7 [0:8];
reg [7:0] s8 [0:8];
reg [7:0] s9 [0:8];

reg [7:0] median_comb;

always @(*) begin

    //Input
        s0[0] = i_p00;
        s0[1] = i_p01;
        s0[2] = i_p02;
        s0[3] = i_p10;
        s0[4] = i_p11;
        s0[5] = i_p12;
        s0[6] = i_p20;
        s0[7] = i_p21;
        s0[8] = i_p22;

    //Layer 0
        if (s0[0] <= s0[1]) begin
            s1[0] = s0[0];
            s1[1] = s0[1];
        end
        else begin
            s1[0] = s0[1];
            s1[1] = s0[0];
        end

        if (s0[2] <= s0[3]) begin
            s1[2] = s0[2];
            s1[3] = s0[3];
        end
        else begin
            s1[2] = s0[3];
            s1[3] = s0[2];
        end

        if (s0[4] <= s0[5]) begin
            s1[4] = s0[4];
            s1[5] = s0[5];
        end
        else begin
            s1[4] = s0[5];
            s1[5] = s0[4];
        end

        if (s0[6] <= s0[7]) begin
            s1[6] = s0[6];
            s1[7] = s0[7];
        end
        else begin
            s1[6] = s0[7];
            s1[7] = s0[6];
        end

        s1[8] = s0[8];


    //Layer 1
        s2[0] = s1[0];

        if (s1[1] <= s1[2]) begin
            s2[1] = s1[1];
            s2[2] = s1[2];
        end
        else begin
            s2[1] = s1[2];
            s2[2] = s1[1];
        end

        if (s1[3] <= s1[4]) begin
            s2[3] = s1[3];
            s2[4] = s1[4];
        end
        else begin
            s2[3] = s1[4];
            s2[4] = s1[3];
        end

        if (s1[5] <= s1[6]) begin
            s2[5] = s1[5];
            s2[6] = s1[6];
        end
        else begin
            s2[5] = s1[6];
            s2[6] = s1[5];
        end

        if (s1[7] <= s1[8]) begin
            s2[7] = s1[7];
            s2[8] = s1[8];
        end
        else begin
            s2[7] = s1[8];
            s2[8] = s1[7];
        end

    // Layer 2
        if (s2[0] <= s2[1]) begin
            s3[0] = s2[0];
            s3[1] = s2[1];
        end
        else begin
            s3[0] = s2[1];
            s3[1] = s2[0];
        end

        if (s2[2] <= s2[3]) begin
            s3[2] = s2[2];
            s3[3] = s2[3];
        end
        else begin
            s3[2] = s2[3];
            s3[3] = s2[2];
        end

        if (s2[4] <= s2[5]) begin
            s3[4] = s2[4];
            s3[5] = s2[5];
        end
        else begin
            s3[4] = s2[5];
            s3[5] = s2[4];
        end

        if (s2[6] <= s2[7]) begin
            s3[6] = s2[6];
            s3[7] = s2[7];
        end
        else begin
            s3[6] = s2[7];
            s3[7] = s2[6];
        end

        s3[8] = s2[8];

    //Layer 3
        s4[0] = s3[0];

        if (s3[1] <= s3[2]) begin
            s4[1] = s3[1];
            s4[2] = s3[2];
        end
        else begin
            s4[1] = s3[2];
            s4[2] = s3[1];
        end

        if (s3[3] <= s3[4]) begin
            s4[3] = s3[3];
            s4[4] = s3[4];
        end
        else begin
            s4[3] = s3[4];
            s4[4] = s3[3];
        end

        if (s3[5] <= s3[6]) begin
            s4[5] = s3[5];
            s4[6] = s3[6];
        end
        else begin
            s4[5] = s3[6];
            s4[6] = s3[5];
        end

        if (s3[7] <= s3[8]) begin
            s4[7] = s3[7];
            s4[8] = s3[8];
        end
        else begin
            s4[7] = s3[8];
            s4[8] = s3[7];
        end

    //Layer 4
        if (s4[0] <= s4[1]) begin
            s5[0] = s4[0];
            s5[1] = s4[1];
        end
        else begin
            s5[0] = s4[1];
            s5[1] = s4[0];
        end

        if (s4[2] <= s4[3]) begin
            s5[2] = s4[2];
            s5[3] = s4[3];
        end
        else begin
            s5[2] = s4[3];
            s5[3] = s4[2];
        end

        if (s4[4] <= s4[5]) begin
            s5[4] = s4[4];
            s5[5] = s4[5];
        end
        else begin
            s5[4] = s4[5];
            s5[5] = s4[4];
        end

        if (s4[6] <= s4[7]) begin
            s5[6] = s4[6];
            s5[7] = s4[7];
        end
        else begin
            s5[6] = s4[7];
            s5[7] = s4[6];
        end

        s5[8] = s4[8];

    //Layer 5
        s6[0] = s5[0];

        if (s5[1] <= s5[2]) begin
            s6[1] = s5[1];
            s6[2] = s5[2];
        end
        else begin
            s6[1] = s5[2];
            s6[2] = s5[1];
        end

        if (s5[3] <= s5[4]) begin
            s6[3] = s5[3];
            s6[4] = s5[4];
        end
        else begin
            s6[3] = s5[4];
            s6[4] = s5[3];
        end

        if (s5[5] <= s5[6]) begin
            s6[5] = s5[5];
            s6[6] = s5[6];
        end
        else begin
            s6[5] = s5[6];
            s6[6] = s5[5];
        end

        if (s5[7] <= s5[8]) begin
            s6[7] = s5[7];
            s6[8] = s5[8];
        end
        else begin
            s6[7] = s5[8];
            s6[8] = s5[7];
        end

    //Layer 6
        if (s6[0] <= s6[1]) begin
            s7[0] = s6[0];
            s7[1] = s6[1];
        end
        else begin
            s7[0] = s6[1];
            s7[1] = s6[0];
        end

        if (s6[2] <= s6[3]) begin
            s7[2] = s6[2];
            s7[3] = s6[3];
        end
        else begin
            s7[2] = s6[3];
            s7[3] = s6[2];
        end

        if (s6[4] <= s6[5]) begin
            s7[4] = s6[4];
            s7[5] = s6[5];
        end
        else begin
            s7[4] = s6[5];
            s7[5] = s6[4];
        end

        if (s6[6] <= s6[7]) begin
            s7[6] = s6[6];
            s7[7] = s6[7];
        end
        else begin
            s7[6] = s6[7];
            s7[7] = s6[6];
        end

        s7[8] = s6[8];

    //Layer 7
        s8[0] = s7[0];

        if (s7[1] <= s7[2]) begin
            s8[1] = s7[1];
            s8[2] = s7[2];
        end
        else begin
            s8[1] = s7[2];
            s8[2] = s7[1];
        end

        if (s7[3] <= s7[4]) begin
            s8[3] = s7[3];
            s8[4] = s7[4];
        end
        else begin
            s8[3] = s7[4];
            s8[4] = s7[3];
        end

        if (s7[5] <= s7[6]) begin
            s8[5] = s7[5];
            s8[6] = s7[6];
        end
        else begin
            s8[5] = s7[6];
            s8[6] = s7[5];
        end

        if (s7[7] <= s7[8]) begin
            s8[7] = s7[7];
            s8[8] = s7[8];
        end
        else begin
            s8[7] = s7[8];
            s8[8] = s7[7];
        end

    //Layer 8
        if (s8[0] <= s8[1]) begin
            s9[0] = s8[0];
            s9[1] = s8[1];
        end
        else begin
            s9[0] = s8[1];
            s9[1] = s8[0];
        end

        if (s8[2] <= s8[3]) begin
            s9[2] = s8[2];
            s9[3] = s8[3];
        end
        else begin
            s9[2] = s8[3];
            s9[3] = s8[2];
        end

        if (s8[4] <= s8[5]) begin
            s9[4] = s8[4];
            s9[5] = s8[5];
        end
        else begin
            s9[4] = s8[5];
            s9[5] = s8[4];
        end

        if (s8[6] <= s8[7]) begin
            s9[6] = s8[6];
            s9[7] = s8[7];
        end
        else begin
            s9[6] = s8[7];
            s9[7] = s8[6];
        end

        s9[8] = s8[8];

    //Output
        median_comb = s9[4];
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_median       <= 8'd0;
            o_median_valid <= 1'b0;
        end
        else begin
            o_median       <= median_comb;
            o_median_valid <= i_window_valid;
        end
    end
endmodule