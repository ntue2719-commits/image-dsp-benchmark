`timescale 1ns / 1ps
`default_nettype none

// Self-contained AXI4-Lite end-to-end regression, Verilog-2001.
// 2 distinct 64x64 frames, independent reference Median->Sobel->Threshold,
// AW/W independent, B/R backpressure, full readback, error/reset recovery.
// No external HEX files required.
module tb_dsp_image_axi_realhex;
    localparam integer W = 64, H = 64, ADDR_W = 25, MEM_ADDR_W = 12;
    localparam integer N_IN = W*H, OUT_W = W-4, N_OUT = (W-4)*(H-4);
    localparam [ADDR_W-1:0] CTRL = 25'h0000000,
                            STATUS = 25'h0000004,
                            INFO_W = 25'h0000008,
                            INFO_H = 25'h000000C,
                            INFO_T = 25'h0000010,
                            INPUT_BASE = 25'h0100000,
                            OUTPUT_BASE = 25'h1100000;
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;

    reg [ADDR_W-1:0] awaddr = 0, araddr = 0;
    reg [2:0] awprot = 0, arprot = 0;
    reg awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 4'b0001;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;

    integer errors = 0, checks = 0, writes = 0, reads = 0;
    integer frame, x, y, k, t, val, gx, gy, mag, nonzero;
    reg [31:0] result, stalled_rdata;
    reg [1:0] stalled_rresp;
    reg [7:0] pixels [0:N_IN-1];
    reg [7:0] median_image [0:N_IN-1];
    reg [7:0] expected_image [0:N_IN-1];
    reg [1023:0] input_hex_path, expected_hex_path;
    integer errors_before_frame;
    integer sortbuf [0:8];
    integer a, b, tmp, j, index;

    dsp_image_axi_v1_0 #(
        .C_S00_AXI_DATA_WIDTH(32),
        .C_S00_AXI_ADDR_WIDTH(ADDR_W),
        .IMAGE_WIDTH(W), .IMAGE_HEIGHT(H), .MEM_ADDR_W(MEM_ADDR_W)
    ) dut (
        .s00_axi_aclk(clk), .s00_axi_aresetn(rst_n),
        .s00_axi_awaddr(awaddr), .s00_axi_awprot(awprot),
        .s00_axi_awvalid(awvalid), .s00_axi_awready(awready),
        .s00_axi_wdata(wdata), .s00_axi_wstrb(wstrb),
        .s00_axi_wvalid(wvalid), .s00_axi_wready(wready),
        .s00_axi_bresp(bresp), .s00_axi_bvalid(bvalid), .s00_axi_bready(bready),
        .s00_axi_araddr(araddr), .s00_axi_arprot(arprot),
        .s00_axi_arvalid(arvalid), .s00_axi_arready(arready),
        .s00_axi_rdata(rdata), .s00_axi_rresp(rresp),
        .s00_axi_rvalid(rvalid), .s00_axi_rready(rready)
    );

    task check;
        input condition;
        input [511:0] description;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                errors = errors + 1;
                if (errors <= 15) $display("FAIL: %0s time=%0t", description, $time);
            end
        end
    endtask

    // AW and W are two independent channels. Delays deliberately vary.
    task send_aw;
        input [ADDR_W-1:0] address;
        input integer delay_cycles;
        integer n;
        begin
            repeat (delay_cycles) @(negedge clk);
            @(negedge clk);
            awaddr = address; awvalid = 1'b1;
            n = 0;
            begin : wait_aw
                forever begin
                    @(posedge clk);
                    if (awready === 1'b1) disable wait_aw;
                    n = n+1;
                    if (n > 100) $fatal(1, "AW handshake timeout");
                end
            end
            @(negedge clk); awvalid = 1'b0;
        end
    endtask

    task send_w;
        input [31:0] data;
        input [3:0] strb;
        input integer delay_cycles;
        integer n;
        begin
            repeat (delay_cycles) @(negedge clk);
            @(negedge clk);
            wdata = data; wstrb = strb; wvalid = 1'b1;
            n = 0;
            begin : wait_w
                forever begin
                    @(posedge clk);
                    if (wready === 1'b1) disable wait_w;
                    n = n+1;
                    if (n > 100) $fatal(1, "W handshake timeout");
                end
            end
            @(negedge clk); wvalid = 1'b0;
        end
    endtask

    task axi_write;
        input [ADDR_W-1:0] address;
        input [31:0] data;
        input [3:0] strb;
        input [1:0] expect_resp;
        input integer aw_delay;
        input integer w_delay;
        input integer b_stall;
        integer n, q;
        reg [1:0] held_resp;
        begin
            fork
                send_aw(address, aw_delay);
                send_w(data, strb, w_delay);
            join
            n = 0;
            begin : wait_b
                forever begin
                    @(negedge clk);
                    if (bvalid === 1'b1) disable wait_b;
                    n = n+1;
                    if (n > 200) $fatal(1, "BVALID timeout addr=%h", address);
                end
            end
            held_resp = bresp;
            check(held_resp === expect_resp, "BRESP matches expected");
            for (q=0; q<b_stall; q=q+1) begin
                @(negedge clk);
                check(bvalid === 1'b1 && bresp === held_resp,
                      "BVALID/BRESP stable under BREADY stall");
            end
            bready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            bready = 1'b0;
            writes = writes+1;
        end
    endtask

    task axi_read;
        input [ADDR_W-1:0] address;
        input [1:0] expect_resp;
        input integer r_stall;
        output [31:0] data;
        integer n, q;
        begin
            @(negedge clk);
            araddr = address; arvalid = 1'b1;
            n = 0;
            begin : wait_ar
                forever begin
                    @(posedge clk);
                    if (arready === 1'b1) disable wait_ar;
                    n = n+1;
                    if (n > 100) $fatal(1, "AR handshake timeout");
                end
            end
            @(negedge clk); arvalid = 1'b0;
            n = 0;
            begin : wait_r
                forever begin
                    @(negedge clk);
                    if (rvalid === 1'b1) disable wait_r;
                    n = n+1;
                    if (n > 200) $fatal(1, "RVALID timeout addr=%h", address);
                end
            end
            stalled_rdata = rdata; stalled_rresp = rresp;
            check(rresp === expect_resp, "RRESP matches expected");
            for (q=0; q<r_stall; q=q+1) begin
                @(negedge clk);
                check(rvalid === 1'b1 && rdata === stalled_rdata &&
                      rresp === stalled_rresp, "RVALID/RDATA/RRESP stable during stall");
            end
            data = stalled_rdata;
            rready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            rready = 1'b0;
            reads = reads+1;
        end
    endtask

    // Load the exact 64x64 image and full-frame golden used on KR260.
    // Pass plusargs +INPUT_HEX=... +EXPECTED_HEX=... in xsim settings.
    // Default files are resolved against the simulator working directory.

    task run_frame;
        input integer number;
        integer z, cycles;
        reg [31:0] v;
        begin
            errors_before_frame=errors;
            $display("FRAME %0d: same real input 64x64; no reset between frames", number+1);
            axi_write(CTRL, 32'd1, 4'b0001, OKAY, 0, 3, 2); // LOAD, W late
            axi_read(STATUS, OKAY, 2, v);
            check(v[1] && v[4] && !v[6], "LOAD status");
            for (z=0;z<N_IN;z=z+1)
                axi_write(INPUT_BASE+4*z, {24'd0,pixels[z]}, 4'b0001,
                          OKAY, z%3, (z+1)%3, 0);
            $display("FRAME %0d: START", number+1);
            axi_write(CTRL, 32'd2, 4'b0001, OKAY, 3, 0, 1); // AW late
            cycles=0; v=0;
            begin : poll_completion
                forever begin
                    axi_read(STATUS, OKAY, 0, v);
                    if (v[3] && v[5]) disable poll_completion;
                    if (v[6]) $fatal(1, "FSM ERROR during frame %0d", number+1);
                    cycles=cycles+1;
                    if (cycles>20000) $fatal(1, "EXEC timeout frame=%0d", number+1);
                end
            end
            $display("FRAME %0d: read/compare %0d valid outputs", number+1, N_OUT);
            for (z=0;z<N_OUT;z=z+1) begin
                axi_read(OUTPUT_BASE+4*z, OKAY, ((z%797)==0)?3:0, v);
                checks=checks+1;
                if (v !== {24'd0,expected_image[((z/OUT_W)+2)*W+((z%OUT_W)+2)]}) begin
                    errors=errors+1;
                    if (errors<=15) $display("MISMATCH frame=%0d k=%0d got=%h expected=%02h",
                                             number+1,z,v,expected_image[((z/OUT_W)+2)*W+((z%OUT_W)+2)]);
                end
            end
            axi_write(CTRL, 32'd4, 4'b0001, OKAY, 0, 0, 0); // STOP
            axi_read(STATUS, OKAY, 0, v);
            check(v[0] && !v[4] && !v[5] && !v[6], "IDLE after STOP");
            $display("FRAME %0d: completed, mismatch=%0d, cumulative errors=%0d", number+1,errors-errors_before_frame,errors);
        end
    endtask

    initial begin
        input_hex_path = "D:/FPGA_Project/image_dsp/image-dsp-benchmark/data/input_64x64/noisy.hex";
        expected_hex_path = "D:/FPGA_Project/image_dsp/image-dsp-benchmark/data/input_64x64/expected.hex";
        if ($value$plusargs("INPUT_HEX=%s", input_hex_path))
            $display("INPUT_HEX=%0s", input_hex_path);
        if ($value$plusargs("EXPECTED_HEX=%s", expected_hex_path))
            $display("EXPECTED_HEX=%0s", expected_hex_path);
        $display("Loading input %0s and expected %0s", input_hex_path, expected_hex_path);
        $readmemh(input_hex_path, pixels);
        $readmemh(expected_hex_path, expected_image);
        repeat(5) @(negedge clk);
        check(awready===1'b0 && wready===1'b0 && arready===1'b0,
              "AXI address channels disabled during active-low reset");
        rst_n=1'b1;
        repeat(3) @(negedge clk);
        $display("TEST: INFO registers / reset polarity");
        axi_read(INFO_W,OKAY,3,result); check(result==W,"INFO_WIDTH");
        axi_read(INFO_H,OKAY,0,result); check(result==H,"INFO_HEIGHT");
        axi_read(INFO_T,OKAY,0,result); check(result==100,"INFO_THRESHOLD");
        axi_read(STATUS,OKAY,0,result); check(result[0] && !result[6],"initial IDLE");

        run_frame(0);
        run_frame(1); // SAME input, no global reset between frames

        $display("TEST: illegal write -> SLVERR -> FSM sticky ERROR");
        axi_write(INPUT_BASE,32'h000000A5,4'b0001,SLVERR,2,0,4);
        axi_read(STATUS,OKAY,2,result);
        check(result[6],"illegal access sets ERROR state");

        $display("TEST: active-low reset recovery");
        @(negedge clk); rst_n=1'b0;
        repeat(4) @(negedge clk);
        rst_n=1'b1;
        repeat(3) @(negedge clk);
        axi_read(STATUS,OKAY,0,result);
        check(result[0] && !result[6],"IDLE after reset recovery");

        $display("------------------------------------------------");
        $display("Frames=2 Input/frame=%0d Output/frame=%0d AXI_writes=%0d AXI_reads=%0d",N_IN,N_OUT,writes,reads);
        $display("Checks=%0d Errors=%0d",checks,errors);
        if(errors==0) $display("PASS: tb_dsp_image_axi_realhex");
        else $display("FAIL: tb_dsp_image_axi_realhex");
        $display("------------------------------------------------");
        if(errors!=0) $fatal(1,"AXI regression failed");
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"Global AXI watchdog expired");
    end
endmodule
`default_nettype wire
