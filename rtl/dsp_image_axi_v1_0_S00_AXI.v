`timescale 1 ns / 1 ps
`default_nettype none
// AXI4-Lite slave adapter for the verified dsp_image_top internal request/ACK bus.
// Single outstanding read and single outstanding write; independent AW/W capture.
// S_AXI_ARESETN is active-low: 0 = reset, 1 = running.
// The active-low reset passes through unchanged into dsp_image_top.
module dsp_image_axi_v1_0_S00_AXI #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 25,
    parameter integer IMAGE_WIDTH = 64,
    parameter integer IMAGE_HEIGHT = 64,
    parameter integer MEM_ADDR_W = 12
)(
    input wire S_AXI_ACLK,
    input wire S_AXI_ARESETN,
    input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input wire [2:0] S_AXI_AWPROT,
    input wire S_AXI_AWVALID,
    output wire S_AXI_AWREADY,
    input wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input wire S_AXI_WVALID,
    output wire S_AXI_WREADY,
    output wire [1:0] S_AXI_BRESP,
    output wire S_AXI_BVALID,
    input wire S_AXI_BREADY,
    input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input wire [2:0] S_AXI_ARPROT,
    input wire S_AXI_ARVALID,
    output wire S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0] S_AXI_RRESP,
    output wire S_AXI_RVALID,
    input wire S_AXI_RREADY
);
    localparam [1:0] WR_COLLECT=2'd0, WR_WAIT=2'd1, WR_RESP=2'd2;
    localparam [1:0] RD_IDLE=2'd0, RD_WAIT=2'd1, RD_RESP=2'd2;
    reg [1:0] wr_state, rd_state;
    reg aw_seen, w_seen;
    reg [C_S_AXI_ADDR_WIDTH-1:0] aw_addr;
    reg [31:0] w_data;
    reg [3:0] w_strb;
    reg wr_req, rd_req;
    reg [C_S_AXI_ADDR_WIDTH-1:0] ar_addr;
    reg [1:0] b_resp, r_resp;
    reg [31:0] r_data;
    wire wr_ack, wr_err, rd_ack, rd_err;
    wire [31:0] rd_result;
    wire unused_irq_done, unused_irq_error;

    assign S_AXI_AWREADY = (wr_state == WR_COLLECT) && !aw_seen && S_AXI_ARESETN;
    assign S_AXI_WREADY  = (wr_state == WR_COLLECT) && !w_seen  && S_AXI_ARESETN;
    assign S_AXI_BVALID  = S_AXI_ARESETN && (wr_state == WR_RESP);
    assign S_AXI_BRESP   = b_resp;
    assign S_AXI_ARREADY = (rd_state == RD_IDLE) && S_AXI_ARESETN;
    assign S_AXI_RVALID  = S_AXI_ARESETN && (rd_state == RD_RESP);
    assign S_AXI_RRESP   = r_resp;
    assign S_AXI_RDATA   = r_data;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            wr_state <= WR_COLLECT;
            aw_seen <= 1'b0;
            w_seen <= 1'b0;
            aw_addr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            w_data <= 32'd0;
            w_strb <= 4'd0;
            wr_req <= 1'b0;
            b_resp <= 2'b00;
        end else begin
            case (wr_state)
                WR_COLLECT: begin
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        aw_addr <= S_AXI_AWADDR;
                        aw_seen <= 1'b1;
                    end
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        w_data <= S_AXI_WDATA;
                        w_strb <= S_AXI_WSTRB;
                        w_seen <= 1'b1;
                    end
                    if (aw_seen && w_seen) begin
                        wr_req <= 1'b1;
                        wr_state <= WR_WAIT;
                    end
                end
                WR_WAIT: begin
                    if (wr_ack) begin
                        wr_req <= 1'b0;
                        b_resp <= wr_err ? 2'b10 : 2'b00; // SLVERR / OKAY
                        wr_state <= WR_RESP;
                    end
                end
                WR_RESP: begin
                    if (S_AXI_BREADY) begin
                        aw_seen <= 1'b0;
                        w_seen <= 1'b0;
                        wr_state <= WR_COLLECT;
                    end
                end
                default: wr_state <= WR_COLLECT;
            endcase
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            rd_state <= RD_IDLE;
            ar_addr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            rd_req <= 1'b0;
            r_resp <= 2'b00;
            r_data <= 32'd0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        ar_addr <= S_AXI_ARADDR;
                        rd_req <= 1'b1;
                        rd_state <= RD_WAIT;
                    end
                end
                RD_WAIT: begin
                    if (rd_ack) begin
                        rd_req <= 1'b0;
                        r_resp <= rd_err ? 2'b10 : 2'b00;
                        r_data <= rd_result;
                        rd_state <= RD_RESP;
                    end
                end
                RD_RESP: begin
                    if (S_AXI_RREADY) rd_state <= RD_IDLE;
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    dsp_image_top #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .MEM_ADDR_W(MEM_ADDR_W)
    ) u_dsp_image_top (
        .i_clk(S_AXI_ACLK), .i_rst_n(S_AXI_ARESETN),
        .i_bus_wr_req(wr_req),
        .i_bus_wr_addr({{(32-C_S_AXI_ADDR_WIDTH){1'b0}},aw_addr}),
        .i_bus_wr_data(w_data), .i_bus_wr_strb(w_strb),
        .o_bus_wr_ack(wr_ack), .o_bus_wr_err(wr_err),
        .i_bus_rd_req(rd_req),
        .i_bus_rd_addr({{(32-C_S_AXI_ADDR_WIDTH){1'b0}},ar_addr}),
        .o_bus_rd_ack(rd_ack), .o_bus_rd_data(rd_result), .o_bus_rd_err(rd_err),
        .o_irq_done(unused_irq_done), .o_irq_error(unused_irq_error)
    );
endmodule
`default_nettype wire
