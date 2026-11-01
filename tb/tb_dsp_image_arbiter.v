`timescale 1ns / 1ps
`default_nettype none
module tb_dsp_image_arbiter;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg wr_req = 0, rd_req = 0;
    reg [31:0] wr_addr = 0, wr_data = 0, rd_addr = 0;
    reg [3:0] wr_strb = 4'b0001;
    wire wr_ack, wr_err, rd_ack, rd_err;
    wire [31:0] rd_data;
    wire load_cmd, start_cmd, stop_cmd, access_error;
    wire in_we;
    wire [11:0] in_waddr;
    wire [7:0] in_wdata;
    wire out_re;
    wire [11:0] out_raddr;
    wire [7:0] out_rdata;
    wire out_rvalid;
    wire [2:0] state;
    wire allow_in, allow_out, busy, done, error, dp_start;
    reg dp_done = 0, dp_error = 0;
    reg out_we = 0;
    reg [11:0] out_waddr = 0;
    reg [7:0] out_wdata = 0;
    integer checks = 0, errors = 0;
    localparam [31:0] INPUT_BASE=32'h00100000, OUTPUT_BASE=32'h01100000;
    dsp_image_arbiter #(.MEM_ADDR_W(12), .IMAGE_WIDTH(64), .IMAGE_HEIGHT(64)) dut (
        .i_clk(clk), .i_rst_n(rst_n),
        .i_bus_wr_req(wr_req), .i_bus_wr_addr(wr_addr), .i_bus_wr_data(wr_data),
        .i_bus_wr_strb(wr_strb), .o_bus_wr_ack(wr_ack), .o_bus_wr_err(wr_err),
        .i_bus_rd_req(rd_req), .i_bus_rd_addr(rd_addr),
        .o_bus_rd_ack(rd_ack), .o_bus_rd_data(rd_data), .o_bus_rd_err(rd_err),
        .i_fsm_state(state), .i_allow_input_write(allow_in),
        .i_allow_output_read(allow_out), .i_fsm_busy(busy), .i_fsm_done(done),
        .i_fsm_error(error), .o_load_cmd(load_cmd), .o_start_cmd(start_cmd),
        .o_stop_cmd(stop_cmd), .o_access_error(access_error),
        .o_in_host_we(in_we), .o_in_host_waddr(in_waddr), .o_in_host_wdata(in_wdata),
        .o_out_host_re(out_re), .o_out_host_raddr(out_raddr),
        .i_out_host_rdata(out_rdata), .i_out_host_rvalid(out_rvalid)
    );
    dsp_image_fsm_ctrl fsm (
        .i_clk(clk), .i_rst_n(rst_n), .i_load_cmd(load_cmd),
        .i_start_cmd(start_cmd), .i_stop_cmd(stop_cmd),
        .i_access_error(access_error), .i_datapath_done(dp_done),
        .i_datapath_error(dp_error), .o_state(state),
        .o_allow_input_write(allow_in), .o_allow_output_read(allow_out),
        .o_datapath_start(dp_start), .o_busy(busy), .o_done(done), .o_error(error)
    );
    dsp_image_output_memory #(.MEM_ADDR_W(12)) output_mem (
        .i_clk(clk), .i_dp_we(out_we), .i_dp_waddr(out_waddr),
        .i_dp_wdata(out_wdata), .i_host_re(out_re), .i_host_raddr(out_raddr),
        .o_host_rdata(out_rdata), .o_host_rvalid(out_rvalid)
    );
    task check;
        input condition;
        input [255:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                errors = errors + 1;
                $display("FAIL: %0s, time=%0t", message, $time);
            end
        end
    endtask
    task write_bus;
        input [31:0] addr, data;
        input [3:0] strb;
        input want_err;
        integer timeout;
        begin
            @(negedge clk); wr_addr=addr; wr_data=data; wr_strb=strb; wr_req=1;
            timeout=0;
            while (!wr_ack && timeout<20) begin @(negedge clk); timeout=timeout+1; end
            check(wr_ack, "write response timeout");
            check(wr_err===want_err, "write ERR aligned to ACK");
            wr_req=0;
            repeat (3) @(negedge clk);
        end
    endtask
    task read_bus;
        input [31:0] addr;
        input [31:0] expected;
        input want_err;
        integer timeout;
        begin
            @(negedge clk); rd_addr=addr; rd_req=1;
            timeout=0;
            while (!rd_ack && timeout<20) begin @(negedge clk); timeout=timeout+1; end
            check(rd_ack, "read response timeout");
            check(rd_err===want_err, "read ERR aligned to ACK");
            if (!want_err) check(rd_data===expected, "read data mismatch");
            rd_req=0;
            repeat (3) @(negedge clk);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        $display("TEST 1: IDLE information and address decode");
        read_bus(32'h4, 32'h1, 0);
        read_bus(32'h8, 64, 0);
        read_bus(32'hC, 64, 0);
        read_bus(32'h10, 100, 0);
        $display("TEST 2: LOAD and host writes");
        write_bus(32'h0, 1, 4'b0001, 0);
        check(state==3'd1, "FSM in LOAD");
        write_bus(INPUT_BASE, 32'h000000A5, 4'b0001, 0);
        check(in_waddr==0 && in_wdata==8'hA5, "first pixel mapped");
        write_bus(INPUT_BASE+4*4095, 32'h34, 4'b0001, 0);
        check(in_waddr==4095 && in_wdata==8'h34, "last pixel mapped");
        $display("TEST 3: EXEC, READ and synchronous output BRAM");
        @(negedge clk); out_we=1; out_waddr=3; out_wdata=8'hB7;
        @(negedge clk); out_we=0;
        write_bus(32'h0, 2, 4'b0001, 0);
        check(state==3'd2, "FSM in EXEC");
        @(negedge clk); dp_done=1;
        @(negedge clk); dp_done=0;
        check(state==3'd3, "FSM in READ");
        read_bus(OUTPUT_BASE+4*3, 32'hB7, 0);
        read_bus(32'h4, 32'h38, 0);
        write_bus(32'h0, 4, 4'b0001, 0);
        check(state==3'd0, "FSM returns to IDLE");
        $display("TEST 4: illegal access and sticky ERROR");
        read_bus(OUTPUT_BASE, 0, 1);
        check(state==3'd4 && error, "illegal access enters ERROR");
        $display("TEST 5: reset recovery and invalid byte strobes");
        @(negedge clk); rst_n=0;
        repeat(2) @(negedge clk);
        rst_n=1;
        write_bus(32'h0, 1, 4'b0011, 1);
        check(error, "invalid strobe raises ERROR");
        $display("--------------------------------------");
        $display("Checks: %0d, Errors: %0d", checks, errors);
        if (!errors) $display("PASS: tb_dsp_image_arbiter");
        else $display("FAIL: tb_dsp_image_arbiter");
        $display("--------------------------------------");
        $finish;
    end
    initial begin #1000000; $display("FAIL: watchdog timeout"); $finish; end
endmodule
`default_nettype wire
