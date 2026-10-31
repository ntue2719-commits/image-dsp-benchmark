`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/24/2026 10:42:12 PM
// Design Name: 
// Module Name: dsp_image_fsm_ctrl
// Phase 2 control FSM; command pulses are provided by the Arbiter.
// All state transitions and reset are synchronous, active-low reset (i_rst_n).
`default_nettype none

module dsp_image_fsm_ctrl (
    input wire              i_clk,
    input wire              i_rst_n,

    input wire              i_load_cmd,
    input wire              i_start_cmd,
    input wire              i_stop_cmd,

    input wire              i_access_error,
    input wire              i_datapath_done,
    input wire              i_datapath_error,
    
    output reg [2:0]        o_state,
    output wire             o_allow_input_write,
    output wire             o_allow_output_read,
    output reg              o_datapath_start,

    output wire             o_busy,
    output wire             o_done,
    output wire             o_error
);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_LOAD = 3'd1;
    localparam [2:0] ST_EXEC = 3'd2;
    localparam [2:0] ST_READ = 3'd3;
    localparam [2:0] ST_ERROR = 3'd4;

    wire cmd_invalid;

    // Arbiter normally rejects illegal commands; this is defense in depth.
    assign cmd_invalid = (i_load_cmd && ((o_state != ST_IDLE) || i_start_cmd || i_stop_cmd)) ||
                         (i_start_cmd && ((o_state != ST_LOAD) || i_stop_cmd)) ||
                         (i_stop_cmd && (o_state != ST_READ));

    assign o_allow_input_write = (o_state == ST_LOAD);
    assign o_allow_output_read = (o_state == ST_READ);

    assign o_busy = (o_state == ST_LOAD) || (o_state == ST_EXEC) || (o_state == ST_READ);

    assign o_done  = (o_state == ST_READ);
    assign o_error = (o_state == ST_ERROR);

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_state          <= ST_IDLE;
            o_datapath_start <= 1'b0;
        end 
        else begin
            o_datapath_start <= 1'b0;
             // Error has priority over all state changes, including DONE.
            if(i_access_error || i_datapath_error || cmd_invalid) begin
                o_state <= ST_ERROR;
            end
            else begin
                case (o_state)
                ST_IDLE: if (i_load_cmd) o_state <= ST_LOAD;
                ST_LOAD: if (i_start_cmd) begin
                    o_state <= ST_EXEC;
                    o_datapath_start <= 1'b1;
                end
                ST_EXEC: if (i_datapath_done) o_state <= ST_READ;
                ST_READ: if (i_stop_cmd) o_state <= ST_IDLE;
                ST_ERROR: o_state <= ST_ERROR;  
                default: o_state <= ST_ERROR;

                endcase
            end
        end
    end


endmodule
`default_nettype wire