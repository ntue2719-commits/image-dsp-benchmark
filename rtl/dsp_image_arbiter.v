`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/24/2026 10:47:26 PM
// Design Name: 
// Module Name: dsp_image_arbiter
// Phase 2 host bus decoder and access authority.
// Requests must remain asserted until ACK and be deasserted before next request.
// A separate one-outstanding-transaction engine is used for reads and writes.
// Active-low synchronous reset at Phase 2 boundary.
module dsp_image_arbiter #(
    parameter MEM_ADDR_W = 12,
    parameter IMAGE_WIDTH = 64,
    parameter IMAGE_HEIGHT = 64,
    parameter THRESHOLD = 100
)(
    input wire i_clk,
    input wire i_rst_n,
    //Write interface
    input wire i_bus_wr_req,
    input wire [31:0] i_bus_wr_addr,
    input wire [31:0] i_bus_wr_data,
    input wire [3:0] i_bus_wr_strb,
    output reg o_bus_wr_ack,
    output reg o_bus_wr_err,
    //Read interface
    input wire i_bus_rd_req,
    input wire [31:0] i_bus_rd_addr,
    output reg o_bus_rd_ack,
    output reg [31:0] o_bus_rd_data,
    output reg o_bus_rd_err,
    //Finite State Machine
    input wire [2:0] i_fsm_state,
    input wire i_allow_input_write,
    input wire i_allow_output_read,
    input wire i_fsm_busy,
    input wire i_fsm_done,
    input wire i_fsm_error,
    //Control outputs
    output reg o_load_cmd,
    output reg o_start_cmd,
    output reg o_stop_cmd,
    output reg o_access_error,
    //Memory interface
    output reg o_in_host_we,
    output reg [MEM_ADDR_W-1:0] o_in_host_waddr,
    output reg [7:0] o_in_host_wdata,
    output reg o_out_host_re,
    output reg [MEM_ADDR_W-1:0] o_out_host_raddr,
    input wire [7:0] i_out_host_rdata,
    input wire i_out_host_rvalid
);

    // Memory-mapped control and information registers.
    localparam [31:0] CTRL           = 32'h00000000;
    localparam [31:0] STATUS         = 32'h00000004;
    localparam [31:0] INFO_WIDTH     = 32'h00000008;
    localparam [31:0] INFO_HEIGHT    = 32'h0000000C;
    localparam [31:0] INFO_THRESHOLD = 32'h00000010;
    localparam [31:0] INPUT_BASE     = 32'h00100000;
    localparam [31:0] OUTPUT_BASE    = 32'h01100000;

    // FSM state encodings used to validate control commands and accesses.
    localparam [2:0] ST_IDLE = 3'd0, ST_LOAD = 3'd1, ST_READ = 3'd3;
    localparam [1:0] WR_IDLE=2'd0, WR_RESP=2'd1, WR_RELEASE=2'd2;
    localparam [1:0] RD_IDLE=2'd0, RD_WAIT=2'd1, RD_RESP=2'd2, RD_RELEASE=2'd3;

    // Independent state machines: one outstanding write and one outstanding read.
    reg [1:0] wr_state, rd_state;
    reg wr_error_pending, rd_error_pending;
    wire wr_input_region, rd_output_region;
    wire [31:0] wr_offset, rd_offset;

    // Decode whether each bus address falls inside its mapped image-memory region.
    assign wr_input_region = (i_bus_wr_addr >= INPUT_BASE) &&
                             (i_bus_wr_addr < INPUT_BASE + (1 << MEM_ADDR_W)*4);
    assign rd_output_region = (i_bus_rd_addr >= OUTPUT_BASE) &&
                              (i_bus_rd_addr < OUTPUT_BASE + (1 << MEM_ADDR_W)*4);
    assign wr_offset = i_bus_wr_addr - INPUT_BASE;
    assign rd_offset = i_bus_rd_addr - OUTPUT_BASE;


    // All state and output registers update on the rising clock edge.
    // Reset is synchronous and active-low.
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            wr_state <= WR_IDLE;
            rd_state <= RD_IDLE;
            wr_error_pending <= 0;
            rd_error_pending <= 0;
            o_bus_wr_ack <= 0;
            o_bus_wr_err <= 0;
            o_bus_rd_ack <= 0;
            o_bus_rd_err <= 0;
            o_bus_rd_data <= 0;
            o_load_cmd <= 0;
            o_start_cmd <= 0;
            o_stop_cmd <= 0;
            o_access_error <= 0;
            o_in_host_we <= 0;
            o_in_host_waddr <= 0;
            o_in_host_wdata <= 0;
            o_out_host_re <= 0;
            o_out_host_raddr <= 0;
        end else begin
            // Default outputs low each cycle; commands and ACK/ERR are one-cycle pulses.
            o_bus_wr_ack <= 0;
            o_bus_wr_err <= 0;
            o_bus_rd_ack <= 0;
            o_bus_rd_err <= 0;
            o_load_cmd <= 0;
            o_start_cmd <= 0;
            o_stop_cmd <= 0;
            o_access_error <= 0;
            o_in_host_we <= 0;
            o_out_host_re <= 0;
            // ---------------- Write transaction FSM ----------------
            case (wr_state)
                // Accept a new write request only while idle.
                WR_IDLE: if (i_bus_wr_req) begin
                    wr_state <= WR_RESP;
                    wr_error_pending <= 0;
                    // Control-register writes issue LOAD, START, or STOP commands.
                    if (i_bus_wr_addr == CTRL && i_bus_wr_strb == 4'b0001) begin
                        case (i_bus_wr_data)
                            32'h00000001: if (i_fsm_state == ST_IDLE) o_load_cmd <= 1;
                                         else begin wr_error_pending <= 1; o_access_error <= 1; end
                            32'h00000002: if (i_fsm_state == ST_LOAD) o_start_cmd <= 1;
                                         else begin wr_error_pending <= 1; o_access_error <= 1; end
                            32'h00000004: if (i_fsm_state == ST_READ) o_stop_cmd <= 1;
                                         else begin wr_error_pending <= 1; o_access_error <= 1; end
                            default: begin wr_error_pending <= 1; o_access_error <= 1; end
                        endcase
                    // Otherwise, validate and forward a single 8-bit input pixel write.
                    end else if (wr_input_region && wr_offset[1:0] == 2'b00 &&
                                 wr_offset[31:2] < IMAGE_WIDTH*IMAGE_HEIGHT &&
                                 i_bus_wr_strb == 4'b0001 && i_allow_input_write) begin
                        o_in_host_we <= 1;
                        o_in_host_waddr <= wr_offset[MEM_ADDR_W+1:2];
                        o_in_host_wdata <= i_bus_wr_data[7:0];
                    end else begin
                        wr_error_pending <= 1;
                        o_access_error <= 1;
                    end
                end
                // Return the result of the accepted write transaction to the host.
                WR_RESP: begin
                    o_bus_wr_ack <= 1;
                    o_bus_wr_err <= wr_error_pending;
                    wr_state <= WR_RELEASE;
                end
                // Do not accept another write until the host deasserts its request.
                WR_RELEASE: if (!i_bus_wr_req) wr_state <= WR_IDLE;
                default: wr_state <= WR_IDLE;
            endcase
            // ---------------- Read transaction FSM ----------------
            case (rd_state)
                // Accept a new read request only while idle.
                RD_IDLE: if (i_bus_rd_req) begin
                    rd_error_pending <= 0;
                    // Register reads are served locally without accessing image memory.
                    if (i_bus_rd_addr == STATUS || i_bus_rd_addr == INFO_WIDTH ||
                        i_bus_rd_addr == INFO_HEIGHT || i_bus_rd_addr == INFO_THRESHOLD ||
                        i_bus_rd_addr == CTRL) begin
                            rd_state <= RD_RESP;
                        case (i_bus_rd_addr)
                            CTRL: o_bus_rd_data <= 0;
                            STATUS: o_bus_rd_data <= {25'd0, i_fsm_error, i_fsm_done, i_fsm_busy,
                                                      (i_fsm_state == ST_READ), (i_fsm_state == 3'd2),
                                                      (i_fsm_state == ST_LOAD), (i_fsm_state == ST_IDLE)};
                            INFO_WIDTH: o_bus_rd_data <= IMAGE_WIDTH;
                            INFO_HEIGHT: o_bus_rd_data <= IMAGE_HEIGHT;
                            default: o_bus_rd_data <= THRESHOLD;
                        endcase
                    // Output-memory reads require a valid address and permission from the FSM.
                    end else if (rd_output_region && rd_offset[1:0] == 2'b00 &&
                                 rd_offset[31:2] < (IMAGE_WIDTH-4)*(IMAGE_HEIGHT-4) &&
                                 i_allow_output_read) begin
                        o_out_host_re <= 1;
                        o_out_host_raddr <= rd_offset[MEM_ADDR_W+1:2];
                        rd_state <= RD_WAIT;
                    end else begin
                        rd_error_pending <= 1;
                        o_access_error <= 1;
                        o_bus_rd_data <= 0;
                        rd_state <= RD_RESP;
                    end
                end
                // Wait for the output memory to indicate that read data is valid.
                RD_WAIT: if (i_out_host_rvalid) begin
                    o_bus_rd_data <= {24'b0, i_out_host_rdata};
                    rd_state <= RD_RESP;
                end
                // Return read data and the transaction status to the host.
                RD_RESP: begin
                    o_bus_rd_ack <= 1;
                    o_bus_rd_err <= rd_error_pending;
                    rd_state <= RD_RELEASE;
                end
                // Wait for the host to deassert its request before accepting another read.
                RD_RELEASE: if (!i_bus_rd_req) rd_state <= RD_IDLE;
                default: rd_state <= RD_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire