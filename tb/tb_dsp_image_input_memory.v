`timescale 1ns / 1ps
`default_nettype none

// Phase 2 unit test: dsp_image_input_memory
// Run as the simulation top in XSim/ModelSim/Icarus.
module tb_dsp_image_input_memory;
    localparam integer MEM_ADDR_W = 12;
    localparam integer MEM_DEPTH  = (1 << MEM_ADDR_W);
    localparam integer CLK_PERIOD = 10;

    reg                    i_clk;
    reg                    i_host_we;
    reg [MEM_ADDR_W-1:0]   i_host_waddr;
    reg [7:0]              i_host_wdata;
    reg                    i_dp_re;
    reg [MEM_ADDR_W-1:0]   i_dp_raddr;
    wire [7:0]             o_dp_rdata;
    wire                   o_dp_rvalid;

    reg [7:0] golden [0:MEM_DEPTH-1];
    integer errors;
    integer checks;
    integer k;
    reg [7:0] held_data;

    dsp_image_input_memory #(
        .MEM_ADDR_W(MEM_ADDR_W)
    ) dut (
        .i_clk(i_clk),
        .i_host_we(i_host_we),
        .i_host_waddr(i_host_waddr),
        .i_host_wdata(i_host_wdata),
        .i_dp_re(i_dp_re),
        .i_dp_raddr(i_dp_raddr),
        .o_dp_rdata(o_dp_rdata),
        .o_dp_rvalid(o_dp_rvalid)
    );

    initial i_clk = 1'b0;
    always #(CLK_PERIOD/2) i_clk = ~i_clk;

    // Deterministic byte pattern, different for adjacent addresses.
    function [7:0] pixel_pattern;
        input integer addr;
        begin
            pixel_pattern = ((addr * 37) + (addr >> 4) + 8'h5A) & 8'hFF;
        end
    endfunction

    task check_valid;
        input expected_valid;
        begin
            checks = checks + 1;
            if (o_dp_rvalid !== expected_valid) begin
                $display("FAIL VALID @ %0t: expected=%b actual=%b",
                         $time, expected_valid, o_dp_rvalid);
                errors = errors + 1;
            end
        end
    endtask

    task write_pixel;
        input integer addr;
        input [7:0] data;
        begin
            @(negedge i_clk);
            i_host_we    = 1'b1;
            i_host_waddr = addr;
            i_host_wdata = data;
            i_dp_re      = 1'b0;
            @(posedge i_clk);
            #1;
            golden[addr] = data;
            check_valid(1'b0);
        end
    endtask

    task read_pixel;
        input integer addr;
        begin
            @(negedge i_clk);
            i_host_we  = 1'b0;
            i_dp_re    = 1'b1;
            i_dp_raddr = addr;
            @(posedge i_clk);
            #1; // Check registered outputs after nonblocking assignments settle.
            check_valid(1'b1);
            checks = checks + 1;
            if (o_dp_rdata !== golden[addr]) begin
                $display("FAIL DATA @ %0t: addr=%0d expected=%02h actual=%02h",
                         $time, addr, golden[addr], o_dp_rdata);
                errors = errors + 1;
            end
        end
    endtask

    task idle_read_cycle;
        begin
            @(negedge i_clk);
            i_host_we = 1'b0;
            i_dp_re   = 1'b0;
            held_data = o_dp_rdata;
            @(posedge i_clk);
            #1;
            check_valid(1'b0);
            checks = checks + 1;
            if (o_dp_rdata !== held_data) begin
                $display("FAIL HOLD @ %0t: expected=%02h actual=%02h",
                         $time, held_data, o_dp_rdata);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        i_host_we    = 1'b0;
        i_host_waddr = {MEM_ADDR_W{1'b0}};
        i_host_wdata = 8'd0;
        i_dp_re      = 1'b0;
        i_dp_raddr   = {MEM_ADDR_W{1'b0}};
        errors       = 0;
        checks       = 0;
        held_data    = 8'd0;

        // No reset port and no memory initialization are specified.
        // All addresses are written before their first data check.
        $display("TEST 1: fill the entire %0d-byte input memory", MEM_DEPTH);
        for (k = 0; k < MEM_DEPTH; k = k + 1)
            write_pixel(k, pixel_pattern(k));

        $display("TEST 2: consecutive synchronous reads / correct order");
        for (k = 0; k < MEM_DEPTH; k = k + 1)
            read_pixel(k);

        $display("TEST 3: read-valid deassertion and output-data hold");
        idle_read_cycle();
        idle_read_cycle();

        $display("TEST 4: discontinuous read requests");
        for (k = 0; k < 32; k = k + 1) begin
            read_pixel((k * 127) % MEM_DEPTH);
            idle_read_cycle();
        end

        $display("TEST 5: overwrite data in LOAD, then read in EXEC");
        write_pixel(0,               8'h00);
        write_pixel(1,               8'hFF);
        write_pixel(MEM_DEPTH / 2,   8'hA5);
        write_pixel(MEM_DEPTH - 1,   8'h3C);
        read_pixel(0);
        read_pixel(1);
        read_pixel(MEM_DEPTH / 2);
        read_pixel(MEM_DEPTH - 1);
        idle_read_cycle();

        $display("----------------------------------------------");
        $display("Checks: %0d, Errors: %0d", checks, errors);
        if (errors == 0)
            $display("PASS: tb_dsp_image_input_memory");
        else
            $display("FAIL: tb_dsp_image_input_memory");
        $display("----------------------------------------------");
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: simulation timeout");
        $finish;
    end
endmodule
`default_nettype wire
