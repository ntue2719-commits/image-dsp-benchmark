`timescale 1ns / 1ps
`default_nettype none

module tb_dsp_image_output_memory;
    localparam integer MEM_ADDR_W = 12;
    localparam integer MEM_DEPTH  = (1 << MEM_ADDR_W);
    localparam integer N_OUTPUT   = (64-4)*(64-4); // dense 60x60 valid region

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg                    dp_we = 1'b0;
    reg [MEM_ADDR_W-1:0]   dp_waddr = {MEM_ADDR_W{1'b0}};
    reg [7:0]              dp_wdata = 8'h00;
    reg                    host_re = 1'b0;
    reg [MEM_ADDR_W-1:0]   host_raddr = {MEM_ADDR_W{1'b0}};
    wire [7:0]             host_rdata;
    wire                   host_rvalid;

    reg [7:0] golden [0:MEM_DEPTH-1];
    integer checks = 0;
    integer errors = 0;
    integer i;
    reg [7:0] held;

    dsp_image_output_memory #(.MEM_ADDR_W(MEM_ADDR_W)) dut (
        .i_clk(clk),
        .i_dp_we(dp_we),
        .i_dp_waddr(dp_waddr),
        .i_dp_wdata(dp_wdata),
        .i_host_re(host_re),
        .i_host_raddr(host_raddr),
        .o_host_rdata(host_rdata),
        .o_host_rvalid(host_rvalid)
    );

    function [7:0] pattern;
        input integer index;
        begin
            pattern = (index * 37 + (index >> 3) + 19) & 8'hff;
        end
    endfunction

    // Drive on falling edge, sample after rising edge to avoid TB/DUT races.
    task write_pixel;
        input integer addr;
        input [7:0] value;
        begin
            @(negedge clk);
            dp_we = 1'b1;
            dp_waddr = addr;
            dp_wdata = value;
            @(posedge clk); #1;
            golden[addr] = value;
            @(negedge clk);
            dp_we = 1'b0;
        end
    endtask

    task read_and_check;
        input integer addr;
        begin
            @(negedge clk);
            host_re = 1'b1;
            host_raddr = addr;
            @(posedge clk); #1;
            checks = checks + 1;
            if (host_rvalid !== 1'b1 || host_rdata !== golden[addr]) begin
                $display("ERROR read addr=%0d got valid=%b data=%02h expected=%02h",
                         addr, host_rvalid, host_rdata, golden[addr]);
                errors = errors + 1;
            end
            @(negedge clk);
            host_re = 1'b0;
        end
    endtask

    initial begin
        // Establish a known valid state; memory content is intentionally not reset.
        @(negedge clk);
        host_re = 1'b0;
        dp_we = 1'b0;
        @(posedge clk); #1;

        $display("TEST 1: datapath writes dense output valid region");
        for (i = 0; i < N_OUTPUT; i = i + 1)
            write_pixel(i, pattern(i));

        $display("TEST 2: consecutive host synchronous reads");
        // Continuous read requests on consecutive clock edges.
        @(negedge clk);
        host_re = 1'b1;
        for (i = 0; i < N_OUTPUT; i = i + 1) begin
            host_raddr = i;
            @(posedge clk); #1;
            checks = checks + 1;
            if (host_rvalid !== 1'b1 || host_rdata !== golden[i]) begin
                $display("ERROR sequential addr=%0d valid=%b got=%02h expected=%02h",
                         i, host_rvalid, host_rdata, golden[i]);
                errors = errors + 1;
            end
            @(negedge clk);
        end
        host_re = 1'b0;

        $display("TEST 3: read-valid low and output held without read");
        held = host_rdata;
        repeat (4) begin
            @(posedge clk); #1;
            checks = checks + 2;
            if (host_rvalid !== 1'b0) begin
                $display("ERROR: rvalid asserted without host read");
                errors = errors + 1;
            end
            if (host_rdata !== held) begin
                $display("ERROR: read data changed without read");
                errors = errors + 1;
            end
        end

        $display("TEST 4: nonconsecutive host reads");
        for (i = 0; i < 100; i = i + 1) begin
            read_and_check((i * 31) % N_OUTPUT);
            @(posedge clk); #1;
            checks = checks + 1;
            if (host_rvalid !== 1'b0) begin
                $display("ERROR: rvalid did not drop during a read gap");
                errors = errors + 1;
            end
        end

        $display("TEST 5: next EXEC overwrites previous output");
        for (i = 0; i < N_OUTPUT; i = i + 1)
            write_pixel(i, ~pattern(i));
        for (i = 0; i < N_OUTPUT; i = i + 1)
            read_and_check(i);

        $display("----------------------------------------------");
        $display("Checks: %0d, Errors: %0d", checks, errors);
        if (errors == 0)
            $display("PASS: tb_dsp_image_output_memory");
        else
            $display("FAIL: tb_dsp_image_output_memory");
        $display("----------------------------------------------");
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: simulation watchdog timeout");
        $finish;
    end
endmodule

`default_nettype wire
