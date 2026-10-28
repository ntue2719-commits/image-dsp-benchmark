`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/24/2026 10:27:10 PM
// Design Name: 
// Module Name: dsp_image_output_memory
// Phase 2 output frame storage (dense valid-region pixels).
// Port A: Datapath write during EXEC.
// Port B: Host synchronous read during READ.
// State-based access permission is enforced by the Arbiter/FSM, not here.
module dsp_image_output_memory #(
    parameter MEM_ADDR_W = 12
)(
    input  wire                  i_clk,

    // Datapath write port
    input  wire                  i_dp_we,
    input  wire [MEM_ADDR_W-1:0] i_dp_waddr,
    input  wire [7:0]            i_dp_wdata,

    // Host read port
    input  wire                  i_host_re,
    input  wire [MEM_ADDR_W-1:0] i_host_raddr,
    output reg  [7:0]            o_host_rdata,
    output reg                   o_host_rvalid
);

    localparam integer MEM_DEPTH = (1 << MEM_ADDR_W);

    (* ram_style = "block" *)
    reg [7:0] mem [0:MEM_DEPTH-1];

    always @(posedge i_clk) begin
        if (i_dp_we)
            mem[i_dp_waddr] <= i_dp_wdata;
    end

    always @(posedge i_clk) begin
        o_host_rvalid <= i_host_re;
        if (i_host_re)
            o_host_rdata <= mem[i_host_raddr];
    end

endmodule

`default_nettype wire