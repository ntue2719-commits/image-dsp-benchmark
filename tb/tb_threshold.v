`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/24/2026 10:21:05 PM
// Design Name: 
// Module Name: dsp_image_input_memory
// Phase 2 input frame storage.
// Port A: host write (permission enforced externally by Arbiter).
// Port B: datapath synchronous read, one-clock registered response.
// Reads and writes are expected in separate FSM phases (LOAD / EXEC).
module dsp_image_input_memory #(
    parameter MEM_ADDR_W = 12
)(
    input  wire                    i_clk,

    // Host write port (Port A)
    input  wire                    i_host_we,
    input  wire [MEM_ADDR_W-1:0]   i_host_waddr,
    input  wire [7:0]              i_host_wdata,

    // Datapath read port (Port B)
    input  wire                    i_dp_re,
    input  wire [MEM_ADDR_W-1:0]   i_dp_raddr,
    output reg  [7:0]              o_dp_rdata,
    output reg                     o_dp_rvalid
);

    localparam integer MEM_DEPTH = (1 << MEM_ADDR_W);

    // Intended as block RAM; no array reset/initialization.
    (* ram_style = "block" *) reg [7:0] mem [0:MEM_DEPTH-1];

    always @(posedge i_clk) begin
        if (i_host_we)
            mem[i_host_waddr] <= i_host_wdata;
    end

    always @(posedge i_clk) begin
        o_dp_rvalid <= i_dp_re;
        if (i_dp_re)
            o_dp_rdata <= mem[i_dp_raddr];
    end

endmodule

`default_nettype wire
