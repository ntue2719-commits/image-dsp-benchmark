`timescale 1ns / 1ps
`default_nettype none

//////////////////////////////////////////////////////////////////////////////////
// Module Name: dsp_image_datapath
// Project Name: Embedded DSP Image Processing Benchmark (Phase 2)
//
// Description:
//   Phase 2 Datapath Controller:
//     - Reads raw pixel stream from Input BRAM in row-major raster order.
//     - Provides a 1-clock clean reset pulse to the frozen Phase 1 core (ST_PREP).
//     - Streams valid pixels into the Phase 1 verified core (image_dsp_top).
//     - Captures valid filtered edge pixels and writes densely into Output BRAM.
//     - Fully compliant with SPEC_PHASE1.md and SPEC_PHASE2.md.
//
// Target Interface:
//   - Synchronous to i_clk with active-high i_rst (per SPEC_PHASE2 §4 & §16).
//   - 1-cycle pulsed o_done upon writing the final output pixel to Output BRAM.
//////////////////////////////////////////////////////////////////////////////////

module dsp_image_datapath #(
    parameter IMAGE_WIDTH  = 64,
    parameter IMAGE_HEIGHT = 64,
    parameter THRESHOLD    = 100,
    parameter COORD_W      = 12,
    parameter MEM_ADDR_W   = 12
)(
    input  wire                    i_clk,
    input  wire                    i_rst,
    input  wire                    i_start,

    // Input Memory Read Port (SPEC_PHASE2 §15 & §16)
    output reg                     o_in_re,
    output reg  [MEM_ADDR_W-1:0]   o_in_raddr,
    input  wire [7:0]              i_in_rdata,
    input  wire                    i_in_rvalid,

    // Output Memory Write Port (SPEC_PHASE2 §16 & §17)
    output reg                     o_out_we,
    output reg  [MEM_ADDR_W-1:0]   o_out_waddr,
    output reg  [7:0]              o_out_wdata,

    // Status Signals to FSM (SPEC_PHASE2 §12 & §16)
    output reg                     o_busy,
    output reg                     o_done,
    output reg                     o_error
);

    // Frame size definitions matching SPEC_PHASE1 §6 and SPEC_PHASE2 §16
    localparam [MEM_ADDR_W:0] N_INPUT  = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam [MEM_ADDR_W:0] N_OUTPUT = (IMAGE_WIDTH - 4) * (IMAGE_HEIGHT - 4);
    localparam [MEM_ADDR_W:0] CAPACITY = (1 << MEM_ADDR_W);

    // State encoding (IDLE, PREP, RUN, COMMIT, ERROR)
    localparam [2:0] ST_IDLE   = 3'd0,
                     ST_PREP   = 3'd1,
                     ST_RUN    = 3'd2,
                     ST_COMMIT = 3'd3,
                     ST_ERROR  = 3'd4;

    reg [2:0] state;
    reg [MEM_ADDR_W:0] requests_sent;
    reg [MEM_ADDR_W:0] inputs_fed;
    reg [MEM_ADDR_W:0] outputs_captured;

    // Reset the Phase 1 pipeline and line buffers for 1 cycle during ST_PREP
    wire core_rst = i_rst || (state == ST_PREP);
    wire core_valid = (state == ST_RUN) && i_in_rvalid;

    wire core_out_valid;
    wire [7:0] core_out_pixel;
    wire [COORD_W-1:0] core_x, core_y;
    wire [11:0] core_out_mag;

    // Instantiate frozen Phase 1 core (image_dsp_top.v)
    image_dsp_top #(
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .THRESHOLD    (THRESHOLD),
        .COORD_W      (COORD_W)
    ) u_phase1_verified_core (
        .i_clk   (i_clk),
        .i_rst   (core_rst),
        .i_valid (core_valid),
        .i_pixel (i_in_rdata),
        .o_valid (core_out_valid),
        .o_pixel (core_out_pixel),
        .o_x     (core_x),
        .o_y     (core_y),
        .o_mag   (core_out_mag)
    );

    always @(posedge i_clk) begin
        if (i_rst) begin
            state            <= ST_IDLE;
            requests_sent    <= {(MEM_ADDR_W+1){1'b0}};
            inputs_fed       <= {(MEM_ADDR_W+1){1'b0}};
            outputs_captured <= {(MEM_ADDR_W+1){1'b0}};
            o_in_re          <= 1'b0;
            o_in_raddr       <= {MEM_ADDR_W{1'b0}};
            o_out_we         <= 1'b0;
            o_out_waddr      <= {MEM_ADDR_W{1'b0}};
            o_out_wdata      <= 8'd0;
            o_busy           <= 1'b0;
            o_done           <= 1'b0;
            o_error          <= 1'b0;
        end else begin
            // Default synchronous 1-cycle strobes
            o_in_re  <= 1'b0;
            o_out_we <= 1'b0;
            o_done   <= 1'b0;

            case (state)
                ST_IDLE: begin
                    o_busy <= 1'b0;
                    if (i_start) begin
                        // Validate parameter constraints per SPEC_PHASE2 §16
                        if (IMAGE_WIDTH < 5 || IMAGE_HEIGHT < 5 ||
                            N_INPUT > CAPACITY || N_OUTPUT > CAPACITY) begin
                            o_error <= 1'b1;
                            state   <= ST_ERROR;
                        end else begin
                            requests_sent    <= {(MEM_ADDR_W+1){1'b0}};
                            inputs_fed       <= {(MEM_ADDR_W+1){1'b0}};
                            outputs_captured <= {(MEM_ADDR_W+1){1'b0}};
                            o_in_raddr       <= {MEM_ADDR_W{1'b0}};
                            o_out_waddr      <= {MEM_ADDR_W{1'b0}};
                            o_out_wdata      <= 8'd0;
                            o_error          <= 1'b0;
                            o_busy           <= 1'b1;
                            state            <= ST_PREP;
                        end
                    end
                end

                ST_PREP: begin
                    // 1-cycle active-high reset supplied to Phase 1 core via core_rst
                    state <= ST_RUN;
                end

                ST_RUN: begin
                    // Trap illegal runtime conditions
                    if (i_start || 
                        (i_in_rvalid && inputs_fed >= N_INPUT) ||
                        (core_out_valid && outputs_captured >= N_OUTPUT)) begin
                        o_error <= 1'b1;
                        o_busy  <= 1'b0;
                        state   <= ST_ERROR;
                    end else begin
                        // Continuous request streaming to Input BRAM
                        if (requests_sent < N_INPUT) begin
                            o_in_re     <= 1'b1;
                            o_in_raddr  <= requests_sent[MEM_ADDR_W-1:0];
                            requests_sent <= requests_sent + 1'b1;
                        end

                        // Count pixels actually accepted by Phase 1 core
                        if (i_in_rvalid) begin
                            inputs_fed <= inputs_fed + 1'b1;
                        end

                        // Capture valid output from Phase 1 core and store densely into Output BRAM
                        if (core_out_valid) begin
                            // Guard check: Final output must not arrive before all inputs are fed
                            if (outputs_captured == (N_OUTPUT - 1'b1) && inputs_fed != N_INPUT) begin
                                o_error <= 1'b1;
                                o_busy  <= 1'b0;
                                state   <= ST_ERROR;
                            end else begin
                                o_out_we    <= 1'b1;
                                o_out_waddr <= outputs_captured[MEM_ADDR_W-1:0];
                                o_out_wdata <= core_out_pixel;
                                outputs_captured <= outputs_captured + 1'b1;

                                if (outputs_captured == (N_OUTPUT - 1'b1)) begin
                                    state <= ST_COMMIT;
                                end
                            end
                        end
                    end
                end

                ST_COMMIT: begin
                    // Final output write is registered into BRAM on this edge
                    o_busy <= 1'b0;
                    o_done <= 1'b1;
                    state  <= ST_IDLE;
                end

                ST_ERROR: begin
                    o_busy  <= 1'b0;
                    o_error <= 1'b1;
                end

                default: begin
                    o_busy  <= 1'b0;
                    o_error <= 1'b1;
                    state   <= ST_ERROR;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
