`timescale 1ns / 1ps
`default_nettype none

module tb_dsp_image_fsm_ctrl;
    localparam [2:0] ST_IDLE=3'd0, ST_LOAD=3'd1, ST_EXEC=3'd2,
                     ST_READ=3'd3, ST_ERROR=3'd4;
    reg i_clk=1'b0;
    always #5 i_clk = ~i_clk;
    reg i_rst_n=1'b1, i_load_cmd=1'b0, i_start_cmd=1'b0,
        i_stop_cmd=1'b0, i_access_error=1'b0,
        i_datapath_done=1'b0, i_datapath_error=1'b0;
    wire [2:0] o_state;
    wire o_allow_input_write, o_allow_output_read, o_datapath_start;
    wire o_busy, o_done, o_error;
    integer checks=0, errors=0, starts=0;

    dsp_image_fsm_ctrl dut (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_load_cmd(i_load_cmd),
        .i_start_cmd(i_start_cmd), .i_stop_cmd(i_stop_cmd),
        .i_access_error(i_access_error), .i_datapath_done(i_datapath_done),
        .i_datapath_error(i_datapath_error), .o_state(o_state),
        .o_allow_input_write(o_allow_input_write),
        .o_allow_output_read(o_allow_output_read),
        .o_datapath_start(o_datapath_start), .o_busy(o_busy),
        .o_done(o_done), .o_error(o_error)
    );

    // Observe outputs after NBA updates at the rising edge.
    task check;
        input [2:0] state;
        input [4:0] flags; // {input_permission,output_permission,busy,done,error}
        input start_pulse;
        begin
            checks=checks+1;
            if (o_state !== state ||
                {o_allow_input_write,o_allow_output_read,o_busy,o_done,o_error} !== flags ||
                o_datapath_start !== start_pulse) begin
                errors=errors+1;
                $display("FAIL @%0t: state=%0d flags=%b start=%b; expected %0d %b %b",
                         $time, o_state,
                         {o_allow_input_write,o_allow_output_read,o_busy,o_done,o_error},
                         o_datapath_start, state,flags,start_pulse);
            end
        end
    endtask

    // Drive on falling edge, sample after following rising edge.
    task step;
        input rst,load,start,stop,access_err,dp_done,dp_err;
        begin
            @(negedge i_clk);
            i_rst_n=!rst; i_load_cmd=load; i_start_cmd=start;
            i_stop_cmd=stop; i_access_error=access_err;
            i_datapath_done=dp_done; i_datapath_error=dp_err;
            @(posedge i_clk); #1;
            if (o_datapath_start) starts=starts+1;
        end
    endtask

    initial begin
        $display("TEST 1: synchronous reset and full legal frame lifecycle");
        step(1,0,0,0,0,0,0); check(ST_IDLE,5'b00000,0);
        step(0,1,0,0,0,0,0); check(ST_LOAD,5'b10100,0);
        step(0,0,0,0,0,0,0); check(ST_LOAD,5'b10100,0);
        step(0,0,1,0,0,0,0); check(ST_EXEC,5'b00100,1);
        step(0,0,0,0,0,0,0); check(ST_EXEC,5'b00100,0);
        step(0,0,0,0,0,1,0); check(ST_READ,5'b01110,0);
        step(0,0,0,0,0,0,0); check(ST_READ,5'b01110,0);
        step(0,0,0,1,0,0,0); check(ST_IDLE,5'b00000,0);
        $display("TEST 2: second frame without reset");
        step(0,1,0,0,0,0,0); check(ST_LOAD,5'b10100,0);
        step(0,0,1,0,0,0,0); check(ST_EXEC,5'b00100,1);
        step(0,0,0,0,0,1,0); check(ST_READ,5'b01110,0);
        step(0,0,0,1,0,0,0); check(ST_IDLE,5'b00000,0);
        checks=checks+1;
        if (starts !== 2) begin
            errors=errors+1; $display("FAIL: datapath starts=%0d expected=2",starts);
        end
        $display("TEST 3: illegal command causes sticky ERROR");
        step(0,0,1,0,0,0,0); check(ST_ERROR,5'b00001,0);
        step(0,0,0,0,0,0,0); check(ST_ERROR,5'b00001,0);
        step(0,1,0,0,0,0,0); check(ST_ERROR,5'b00001,0);
        step(1,0,0,0,0,0,0); check(ST_IDLE,5'b00000,0);
        $display("TEST 4: access error and datapath error");
        step(0,1,0,0,0,0,0); check(ST_LOAD,5'b10100,0);
        step(0,0,0,0,1,0,0); check(ST_ERROR,5'b00001,0);
        step(1,0,0,0,0,0,0); check(ST_IDLE,5'b00000,0);
        step(0,1,0,0,0,0,0); check(ST_LOAD,5'b10100,0);
        step(0,0,1,0,0,0,0); check(ST_EXEC,5'b00100,1);
        step(0,0,0,0,0,0,1); check(ST_ERROR,5'b00001,0);
        step(1,0,0,0,0,0,0); check(ST_IDLE,5'b00000,0);
        $display("TEST 5: simultaneous conflicting commands and priority");
        step(0,1,1,0,0,0,0); check(ST_ERROR,5'b00001,0);
        step(1,0,0,0,0,0,0); check(ST_IDLE,5'b00000,0);
        step(0,1,0,0,0,0,0); check(ST_LOAD,5'b10100,0);
        step(0,0,1,0,1,0,0); check(ST_ERROR,5'b00001,0);
        $display("----------------------------------------------");
        $display("Checks: %0d, Errors: %0d",checks,errors);
        if (errors==0) $display("PASS: tb_dsp_image_fsm_ctrl");
        else $display("FAIL: tb_dsp_image_fsm_ctrl");
        $display("----------------------------------------------");
        $finish;
    end
endmodule
`default_nettype wire
