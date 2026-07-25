`timescale 1 ns / 1 ps

module cnn_accelerator #
(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 5
)
(
    //========================================================
    // Clock / Reset
    //=========================================================

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 S00_AXI_CLK CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S00_AXI:S_AXIS:M_AXIS, ASSOCIATED_RESET S00_AXI_ARESETN, FREQ_HZ 100000000" *)
    input wire s00_axi_aclk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 S00_AXI_ARESETN RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire s00_axi_aresetn,

    //=========================================================
    // AXI4-Lite Slave Interface
    //=========================================================

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWADDR" *)
    input wire [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_awaddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWPROT" *)
    input wire [2:0] s00_axi_awprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWVALID" *)
    input wire s00_axi_awvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWREADY" *)
    output wire s00_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WDATA" *)
    input wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_wdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WSTRB" *)
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1:0] s00_axi_wstrb,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WVALID" *)
    input wire s00_axi_wvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WREADY" *)
    output wire s00_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI BRESP" *)
    output wire [1:0] s00_axi_bresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI BVALID" *)
    output wire s00_axi_bvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI BREADY" *)
    input wire s00_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARADDR" *)
    input wire [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_araddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARPROT" *)
    input wire [2:0] s00_axi_arprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARVALID" *)
    input wire s00_axi_arvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARREADY" *)
    output wire s00_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RDATA" *)
    output wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_rdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RRESP" *)
    output wire [1:0] s00_axi_rresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RVALID" *)
    output wire s00_axi_rvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RREADY" *)
    input wire s00_axi_rready,

    //=========================================================
    // AXI4-Stream Slave
    //=========================================================

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
    input wire [31:0] s_axis_tdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
    input wire s_axis_tvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
    output wire s_axis_tready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *)
    input wire s_axis_tlast,

    //=========================================================
    // AXI4-Stream Master
    //=========================================================

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [31:0] m_axis_tdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire m_axis_tvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input wire m_axis_tready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire m_axis_tlast
);

    wire rst = ~s00_axi_aresetn;

    wire unused_axi_sideband =
        |s00_axi_awprot |
        |s00_axi_arprot |
        |s00_axi_wstrb;

    cnn_accelerator_top #(
        .PIX_WIDTH    (8),
        .WEIGHT_WIDTH (8),
        .ACC_WIDTH    (32),
        .KERNEL_SIZE  (3),
        .W_ADDR_WIDTH (10),
        .LB_MAX_WIDTH (1024),
        .FIFO_DEPTH   (2048),
        .AXI_ADDR_W   (C_S00_AXI_ADDR_WIDTH),
        .AXI_DATA_W   (C_S00_AXI_DATA_WIDTH)
    )
    u_cnn_accelerator_top
    (
        .clk                    (s00_axi_aclk),
        .rst                    (rst),

        .s_axi_awaddr           (s00_axi_awaddr),
        .s_axi_awvalid          (s00_axi_awvalid),
        .s_axi_awready          (s00_axi_awready),
        .s_axi_wdata            (s00_axi_wdata),
        .s_axi_wvalid           (s00_axi_wvalid),
        .s_axi_wready           (s00_axi_wready),
        .s_axi_bresp            (s00_axi_bresp),
        .s_axi_bvalid           (s00_axi_bvalid),
        .s_axi_bready           (s00_axi_bready),
        .s_axi_araddr           (s00_axi_araddr),
        .s_axi_arvalid          (s00_axi_arvalid),
        .s_axi_arready          (s00_axi_arready),
        .s_axi_rdata            (s00_axi_rdata),
        .s_axi_rresp            (s00_axi_rresp),
        .s_axi_rvalid           (s00_axi_rvalid),
        .s_axi_rready           (s00_axi_rready),

        .s_axis_tdata           (s_axis_tdata),
        .s_axis_tvalid          (s_axis_tvalid),
        .s_axis_tready          (s_axis_tready),
        .s_axis_tlast           (s_axis_tlast),

        .m_axis_tdata           (m_axis_tdata),
        .m_axis_tvalid          (m_axis_tvalid),
        .m_axis_tready          (m_axis_tready),
        .m_axis_tlast           (m_axis_tlast),

        .ext_weight_wr_en       (1'b0),
        .ext_weight_wr_data     (8'sd0),
        .ext_weight_wr_base_addr(10'd0),
        .ext_weight_wr_index    (4'd0)
    );

endmodule