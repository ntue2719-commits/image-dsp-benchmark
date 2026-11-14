`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/24/2026 10:53:58 PM
// Design Name: 
// Module Name: dsp_image_top
// Phase 2 bus-independent accelerator top.
// The AXI4-Lite wrapper terminates AXI handshakes and drives this request/ACK bus.
// Active-low synchronous reset: i_rst_n=0 asserts reset, i_rst_n=1 runs.
module dsp_image_top #(
    parameter IMAGE_WIDTH  = 64,
    parameter IMAGE_HEIGHT = 64,
    parameter MEM_ADDR_W   = 12
)(
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        i_bus_wr_req,
    input  wire [31:0] i_bus_wr_addr,
    input  wire [31:0] i_bus_wr_data,
    input  wire [3:0]  i_bus_wr_strb,
    output wire        o_bus_wr_ack,
    output wire        o_bus_wr_err,
    input  wire        i_bus_rd_req,
    input  wire [31:0] i_bus_rd_addr,
    output wire        o_bus_rd_ack,
    output wire [31:0] o_bus_rd_data,
    output wire        o_bus_rd_err,
    output wire        o_irq_done,
    output wire        o_irq_error
);
    wire [2:0] fsm_state;
    wire allow_input_write, allow_output_read;
    wire fsm_busy, fsm_done, fsm_error;
    wire load_cmd, start_cmd, stop_cmd, access_error;
    wire datapath_start, datapath_busy, datapath_done, datapath_error;

    wire in_host_we;
    wire [MEM_ADDR_W-1:0] in_host_waddr;
    wire [7:0] in_host_wdata;
    wire in_dp_re;
    wire [MEM_ADDR_W-1:0] in_dp_raddr;
    wire [7:0] in_dp_rdata;
    wire in_dp_rvalid;

    wire out_dp_we;
    wire [MEM_ADDR_W-1:0] out_dp_waddr;
    wire [7:0] out_dp_wdata;
    wire out_host_re;
    wire [MEM_ADDR_W-1:0] out_host_raddr;
    wire [7:0] out_host_rdata;
    wire out_host_rvalid;

    assign o_irq_done  = fsm_done;
    assign o_irq_error = fsm_error;

    dsp_image_arbiter #(
        .MEM_ADDR_W(MEM_ADDR_W),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .THRESHOLD(100)
    ) u_arbiter (
        .i_clk(i_clk), .i_rst_n(i_rst_n),
        .i_bus_wr_req(i_bus_wr_req),
        .i_bus_wr_addr(i_bus_wr_addr),
        .i_bus_wr_data(i_bus_wr_data),
        .i_bus_wr_strb(i_bus_wr_strb),
        .o_bus_wr_ack(o_bus_wr_ack),
        .o_bus_wr_err(o_bus_wr_err),
        .i_bus_rd_req(i_bus_rd_req),
        .i_bus_rd_addr(i_bus_rd_addr),
        .o_bus_rd_ack(o_bus_rd_ack),
        .o_bus_rd_data(o_bus_rd_data),
        .o_bus_rd_err(o_bus_rd_err),
        .i_fsm_state(fsm_state),
        .i_allow_input_write(allow_input_write),
        .i_allow_output_read(allow_output_read),
        .i_fsm_busy(fsm_busy),
        .i_fsm_done(fsm_done),
        .i_fsm_error(fsm_error),
        .o_load_cmd(load_cmd),
        .o_start_cmd(start_cmd),
        .o_stop_cmd(stop_cmd),
        .o_access_error(access_error),
        .o_in_host_we(in_host_we),
        .o_in_host_waddr(in_host_waddr),
        .o_in_host_wdata(in_host_wdata),
        .o_out_host_re(out_host_re),
        .o_out_host_raddr(out_host_raddr),
        .i_out_host_rdata(out_host_rdata),
        .i_out_host_rvalid(out_host_rvalid)
    );

    dsp_image_fsm_ctrl u_fsm (
        .i_clk(i_clk), .i_rst_n(i_rst_n),
        .i_load_cmd(load_cmd),
        .i_start_cmd(start_cmd),
        .i_stop_cmd(stop_cmd),
        .i_access_error(access_error),
        .i_datapath_done(datapath_done),
        .i_datapath_error(datapath_error),
        .o_state(fsm_state),
        .o_allow_input_write(allow_input_write),
        .o_allow_output_read(allow_output_read),
        .o_datapath_start(datapath_start),
        .o_busy(fsm_busy),
        .o_done(fsm_done),
        .o_error(fsm_error)
    );

    dsp_image_input_memory #(.MEM_ADDR_W(MEM_ADDR_W)) u_input_memory (
        .i_clk(i_clk),
        .i_host_we(in_host_we),
        .i_host_waddr(in_host_waddr),
        .i_host_wdata(in_host_wdata),
        .i_dp_re(in_dp_re),
        .i_dp_raddr(in_dp_raddr),
        .o_dp_rdata(in_dp_rdata),
        .o_dp_rvalid(in_dp_rvalid)
    );

    dsp_image_datapath #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .MEM_ADDR_W(MEM_ADDR_W)
    ) u_datapath (
        .i_clk(i_clk), .i_rst_n(i_rst_n),
        .i_start(datapath_start),
        .o_in_re(in_dp_re),
        .o_in_raddr(in_dp_raddr),
        .i_in_rdata(in_dp_rdata),
        .i_in_rvalid(in_dp_rvalid),
        .o_out_we(out_dp_we),
        .o_out_waddr(out_dp_waddr),
        .o_out_wdata(out_dp_wdata),
        .o_busy(datapath_busy),
        .o_done(datapath_done),
        .o_error(datapath_error)
    );

    dsp_image_output_memory #(.MEM_ADDR_W(MEM_ADDR_W)) u_output_memory (
        .i_clk(i_clk),
        .i_dp_we(out_dp_we),
        .i_dp_waddr(out_dp_waddr),
        .i_dp_wdata(out_dp_wdata),
        .i_host_re(out_host_re),
        .i_host_raddr(out_host_raddr),
        .o_host_rdata(out_host_rdata),
        .o_host_rvalid(out_host_rvalid)
    );
endmodule
`default_nettype wire


