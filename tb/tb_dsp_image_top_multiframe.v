`timescale 1ns / 1ps
`default_nettype none

// Phase 2 multi-frame regression (single global reset, two different images).
// Frame 1: existing 512x512 noisy.hex, compared with expected.hex.
// Frame 2: all-zero pixels, whose Median->Sobel->Threshold output must be zero.
// No RTL modifications or global reset between frames.
module tb_dsp_image_top_multiframe;
    localparam integer W = 512;
    localparam integer H = 512;
    localparam integer N_INPUT = W * H;
    localparam integer N_OUTPUT = (W-4) * (H-4);
    localparam integer EXEC_TIMEOUT_CYCLES = N_INPUT * 8;
    localparam [31:0] CTRL = 32'h0000_0000;
    localparam [31:0] STATUS = 32'h0000_0004;
    localparam [31:0] INPUT_BASE = 32'h0010_0000;
    localparam [31:0] OUTPUT_BASE = 32'h0110_0000;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg wr_req = 0, rd_req = 0;
    reg [31:0] wr_addr = 0, wr_data = 0, rd_addr = 0;
    reg [3:0] wr_strb = 4'b0001;
    wire wr_ack, wr_err, rd_ack, rd_err;
    wire [31:0] rd_data;
    wire irq_done, irq_error;

    reg [7:0] input_pixels [0:N_INPUT-1];
    reg [7:0] expected_pixels [0:N_INPUT-1];
    integer errors = 0;
    integer checks = 0;
    integer total_reads = 0;
    integer frame_reads;
    integer i, k, x, y, timeout;
    reg [31:0] result;

    dsp_image_top #(
        .IMAGE_WIDTH(W), .IMAGE_HEIGHT(H), .MEM_ADDR_W(18)
    ) dut (
        .i_clk(clk), .i_rst_n(rst_n),
        .i_bus_wr_req(wr_req), .i_bus_wr_addr(wr_addr),
        .i_bus_wr_data(wr_data), .i_bus_wr_strb(wr_strb),
        .o_bus_wr_ack(wr_ack), .o_bus_wr_err(wr_err),
        .i_bus_rd_req(rd_req), .i_bus_rd_addr(rd_addr),
        .o_bus_rd_ack(rd_ack), .o_bus_rd_data(rd_data),
        .o_bus_rd_err(rd_err), .o_irq_done(irq_done),
        .o_irq_error(irq_error)
    );

    task assert_true;
        input condition;
        input [255:0] label;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                errors = errors + 1;
                if (errors <= 16)
                    $display("FAIL: %0s at %0t", label, $time);
            end
        end
    endtask

    task fail_and_stop;
        input [255:0] label;
        begin
            errors = errors + 1;
            $display("FAIL: %0s at %0t", label, $time);
            $display("Checks=%0d Errors=%0d", checks, errors);
            $display("FAIL: tb_dsp_image_top_multiframe");
            $finish;
        end
    endtask

    task bus_write;
        input [31:0] addr;
        input [31:0] data;
        integer t;
        begin
            @(negedge clk);
            wr_addr = addr;
            wr_data = data;
            wr_strb = 4'b0001;
            wr_req = 1'b1;
            t = 0;
            while (wr_ack !== 1'b1 && t < 30) begin
                @(negedge clk);
                t = t + 1;
            end
            if (wr_ack !== 1'b1)
                fail_and_stop("bus write ACK timeout");
            if (wr_err !== 1'b0)
                fail_and_stop("unexpected bus write ERR");
            wr_req = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task bus_read;
        input [31:0] addr;
        output [31:0] data;
        integer t;
        begin
            @(negedge clk);
            rd_addr = addr;
            rd_req = 1'b1;
            t = 0;
            while (rd_ack !== 1'b1 && t < 30) begin
                @(negedge clk);
                t = t + 1;
            end
            if (rd_ack !== 1'b1)
                fail_and_stop("bus read ACK timeout");
            if (rd_err !== 1'b0)
                fail_and_stop("unexpected bus read ERR");
            data = rd_data;
            rd_req = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task execute_frame;
        input integer frame_id;
        begin
            $display("FRAME %0d: START and wait for EXEC -> READ", frame_id);
            bus_write(CTRL, 32'd2);
            timeout = 0;
            while (irq_done !== 1'b1 && irq_error !== 1'b1 &&
                   timeout < EXEC_TIMEOUT_CYCLES) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (irq_error === 1'b1)
                fail_and_stop("FSM ERROR during frame EXEC");
            if (irq_done !== 1'b1)
                fail_and_stop("frame EXEC timeout (check datapath restart)");
            bus_read(STATUS, result);
            assert_true(result[3] && result[5] && !result[6], "READ/DONE status");
        end
    endtask

    task verify_output;
        input integer frame_id;
        reg [7:0] expected_value;
        begin
            frame_reads = 0;
            $display("FRAME %0d: read and compare %0d output pixels", frame_id, N_OUTPUT);
            for (k = 0; k < N_OUTPUT; k = k + 1) begin
                bus_read(OUTPUT_BASE + (k*4), result);
                x = 2 + k % (W-4);
                y = 2 + k / (W-4);
                if (frame_id == 1)
                    expected_value = expected_pixels[y*W+x];
                else
                    expected_value = 8'd0;
                checks = checks + 1;
                if (result !== {24'd0, expected_value}) begin
                    errors = errors + 1;
                    if (errors <= 16)
                        $display("MISMATCH frame=%0d k=%0d x=%0d y=%0d got=%08h exp=%02h",
                                 frame_id, k, x, y, result, expected_value);
                end
                frame_reads = frame_reads + 1;
                total_reads = total_reads + 1;
            end
            assert_true(frame_reads == N_OUTPUT, "frame output read count");
            if (errors != 0)
                fail_and_stop("output golden mismatch");
            $display("FRAME %0d: golden comparison PASS", frame_id);
        end
    endtask

    task finish_frame;
        input integer frame_id;
        begin
            $display("FRAME %0d: STOP -> IDLE", frame_id);
            bus_write(CTRL, 32'd4);
            bus_read(STATUS, result);
            assert_true(result[0] && !result[4] && !result[5] && !result[6],
                        "IDLE after STOP");
        end
    endtask

    initial begin
        $readmemh("D:/FPGA_Project/image_dsp/image-dsp-benchmark/data/input_512x512/noisy.hex", input_pixels);
        $readmemh("D:/FPGA_Project/image_dsp/image-dsp-benchmark/data/input_512x512/expected.hex", expected_pixels);

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        $display("MULTI-FRAME TEST: 512x512, global reset used only once");

        // Frame 1: original image and reference golden.
        $display("FRAME 1: LOAD noisy.hex (%0d pixels)", N_INPUT);
        bus_write(CTRL, 32'd1);
        bus_read(STATUS, result);
        assert_true(result[1], "LOAD state frame 1");
        for (i = 0; i < N_INPUT; i = i + 1)
            bus_write(INPUT_BASE + (i*4), {24'd0, input_pixels[i]});
        execute_frame(1);
        verify_output(1);
        finish_frame(1);

        // Frame 2: distinct all-zero image, same fixed dimensions.
        // All-zero input must produce all-zero Sobel/threshold output.
        // This detects stale output memory / stale pipeline data.
        $display("FRAME 2: LOAD all-zero image (%0d pixels), NO RESET", N_INPUT);
        bus_write(CTRL, 32'd1);
        bus_read(STATUS, result);
        assert_true(result[1], "LOAD state frame 2");
        for (i = 0; i < N_INPUT; i = i + 1)
            bus_write(INPUT_BASE + (i*4), 32'd0);
        execute_frame(2);
        verify_output(2);
        finish_frame(2);

        $display("------------------------------------------------");
        $display("Frames=2 Inputs=%0d Outputs=%0d Reads=%0d",
                 2*N_INPUT, 2*N_OUTPUT, total_reads);
        $display("Checks=%0d Errors=%0d", checks, errors);
        if (errors == 0)
            $display("PASS: tb_dsp_image_top_multiframe");
        else
            $display("FAIL: tb_dsp_image_top_multiframe");
        $display("------------------------------------------------");
        $finish;
    end

    initial begin
        #1000000000;
        fail_and_stop("global watchdog timeout");
    end
endmodule
`default_nettype wire
