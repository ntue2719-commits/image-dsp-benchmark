
`timescale 1ns / 1ps

module dsp_image_output_memory #(
    parameter MEM_ADDR_W = 12                   // each ram address has 12 bit , have sum 2^12 = 4096 address
)(
    input  wire                  i_clk,         //clk control ram 

    input  wire                  i_dp_we,       // if = 1 -> DSP can write 
    input  wire [MEM_ADDR_W-1:0] i_dp_waddr,    // address which DSP want to write 
    input  wire [7:0]            i_dp_wdata,    // pixel 8 bit need write

    input  wire                  i_host_re,         // if = 1 -> host request read
    input  wire [MEM_ADDR_W-1:0] i_host_raddr,      // address which host want to read 
    output reg  [7:0]            o_host_rdata,      // data pixel host receive
    output reg                   o_host_rvalid      // = 1 when data read is valid 
);

    localparam integer MEM_DEPTH = (1 << MEM_ADDR_W);      // shift 1 bit to the left 12 position 

    (* ram_style = "block" *)
    reg [7:0] mem [0:MEM_DEPTH-1];              // reg [7:0] : each cell have 1 pixel 8 bit
                                                //  mem [0:MEM_DEPTH-1]; : have 4096 cell
    always @(posedge i_clk) begin
        if (i_dp_we)                            // i_dp_we = 1 -> write, 0 -> not write , old data still there 
            mem[i_dp_waddr] <= i_dp_wdata;      // write the value of pixel 8 bit to the address which DSP w to write
    end

    always @(posedge i_clk) begin
        o_host_rvalid <= i_host_re;
        if (i_host_re)                              // i_host_re = 1 , 0 -> o_host_rdata keep the old value but o_host_rvalid = 0
            o_host_rdata <= mem[i_host_raddr];
    end

endmodule

`default_nettype wire
