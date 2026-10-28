`timescale 1ns / 1ps

module tb_image_dsp;

    parameter W       = 640;
    parameter H       = 480;
    parameter GAPS    = 0;
    parameter NFRAMES = 1;

    localparam N = W * H;

    reg clk   = 0;
    reg rst   = 1;
    reg valid = 0;
    reg [7:0] pix = 0;

    always #5 clk = ~clk;

    wire        o_valid;
    wire [7:0]  o_pixel;
    wire [11:0] o_x;
    wire [11:0] o_y;
    wire [11:0] o_mag;

    image_dsp_top #(
        .IMAGE_WIDTH (W),
        .IMAGE_HEIGHT(H)
    ) dut (
        .i_clk   (clk),
        .i_rst   (rst),
        .i_valid (valid),
        .i_pixel (pix),

        .o_valid (o_valid),
        .o_pixel (o_pixel),
        .o_x     (o_x),
        .o_y     (o_y),
        .o_mag   (o_mag)
    );

    // ============================================================
    // Memories
    // ============================================================

    reg [7:0]  in_mem     [0:N-1];
    reg [7:0]  exp_mem    [0:N-1];
    reg [15:0] grad_mem   [0:N-1];

    // Full-frame RTL output buffer
    reg [7:0] rtl_mem [0:N-1];

    integer sent   = 0;
    integer count  = 0;
    integer errors = 0;

    integer ex;
    integer ey;
    integer k;

    integer i;
    integer rtl_file;


    // ============================================================
    // Input driver
    // ============================================================

    always @(posedge clk) begin
        if (rst) begin
            valid <= 0;
        end
        else if (
            sent < N * NFRAMES &&
            (!GAPS || (($random & 3) != 0))
        ) begin

            valid <= 1;
            pix   <= in_mem[sent % N];
            sent  <= sent + 1;

        end
        else begin
            valid <= 0;
        end
    end


    // ============================================================
    // Checker + capture RTL output into full-frame buffer
    // ============================================================

    always @(posedge clk) begin

        if (!rst && o_valid) begin

            // k-th valid Sobel output
            k = count % ((W - 4) * (H - 4));

            ex = 2 + (k % (W - 4));
            ey = 2 + (k / (W - 4));


            // ----------------------------------------------------
            // Coordinate check
            // ----------------------------------------------------

            if (o_x !== ex || o_y !== ey) begin

                errors = errors + 1;

                if (errors < 10)
                    $display(
                        "COORD #%0d got (%0d,%0d) exp (%0d,%0d)",
                        count,
                        o_x,
                        o_y,
                        ex,
                        ey
                    );

            end
            else begin

                // ------------------------------------------------
                // Store RTL pixel into correct full-frame position
                // ------------------------------------------------

                rtl_mem[ey * W + ex] = o_pixel;


                // ------------------------------------------------
                // Pixel check
                // ------------------------------------------------

                if (o_pixel !== exp_mem[ey * W + ex]) begin

                    errors = errors + 1;

                    if (errors < 10)
                        $display(
                            "PIXEL (%0d,%0d) got %0d exp %0d",
                            ex,
                            ey,
                            o_pixel,
                            exp_mem[ey * W + ex]
                        );

                end


                // ------------------------------------------------
                // Gradient magnitude check
                // ------------------------------------------------

                if ({4'b0, o_mag} !== grad_mem[ey * W + ex]) begin

                    errors = errors + 1;

                    if (errors < 10)
                        $display(
                            "MAG (%0d,%0d) got %0d exp %0d",
                            ex,
                            ey,
                            o_mag,
                            grad_mem[ey * W + ex]
                        );

                end

            end

            count = count + 1;

        end

    end


    // ============================================================
    // Main test sequence
    // ============================================================

    initial begin

        // --------------------------------------------------------
        // Load golden/input files
        // --------------------------------------------------------

        $readmemh(
            "D:/Downloads/project DSP/python/noisy.hex",
            in_mem
        );

        $readmemh(
            "D:/Downloads/project DSP/python/expected.hex",
            exp_mem
        );

        $readmemh(
            "D:/Downloads/project DSP/python/gradient.hex",
            grad_mem
        );


        // --------------------------------------------------------
        // Initialize full-frame RTL output to zero
        //
        // Border pixels therefore remain 00:
        //
        // x = 0,1,W-2,W-1
        // y = 0,1,H-2,H-1
        //
        // matching Python expected.hex
        // --------------------------------------------------------

        for (i = 0; i < N; i = i + 1) begin
            rtl_mem[i] = 8'h00;
        end


        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------

        repeat (5)
            @(posedge clk);

        rst <= 0;


        // --------------------------------------------------------
        // Wait until all pixels are sent
        // --------------------------------------------------------

        wait (sent == N * NFRAMES);


        // --------------------------------------------------------
        // Flush pipeline
        // --------------------------------------------------------

        repeat (50)
            @(posedge clk);


// --------------------------------------------------------
// Print summary
// --------------------------------------------------------

$display("");

$display(
    "W=%0d H=%0d GAPS=%0d frames=%0d : outputs=%0d (expected %0d) errors=%0d",
    W,
    H,
    GAPS,
    NFRAMES,
    count,
    NFRAMES * (W - 4) * (H - 4),
    errors
);

if (
    errors == 0 &&
    count == NFRAMES * (W - 4) * (H - 4)
) begin
    $display("PASS");
end
else begin
    $display("FAIL");
end


// --------------------------------------------------------
// Write FULL-FRAME rtl_result.hex
// --------------------------------------------------------

rtl_file = $fopen(
    "D:/Downloads/project DSP/python/rtl_result.hex",
    "w"
);

if (rtl_file == 0) begin
    $display("ERROR: Cannot open rtl_result.hex");
    $finish;
end

for (i = 0; i < N; i = i + 1) begin
    $fdisplay(
        rtl_file,
        "%02x",
        rtl_mem[i]
    );
end

$fclose(rtl_file);

$display("rtl_result.hex written successfully.");
$display("rtl_result.hex pixels = %0d", N);

$display("");

$finish;

    end

endmodule