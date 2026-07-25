`timescale 1ns / 1ps
//==================================================================
// AXI4-Lite slave: control/status register file for the CNN top
// module. Register map (word-addressed, 4-byte aligned):
//   0x00  CTRL     [0]=start (self-clearing pulse), RW
//   0x04  STATUS   [0]=done, [1]=busy, RO
//   0x08  IMG_WIDTH        RW
//   0x0C  IMG_HEIGHT       RW
//   0x10  KERNEL_BASE_ADDR RW
//   0x14  WEIGHT_BASE_ADDR RW
//   0x18  WEIGHT_INDEX     RW
//   0x1C  WEIGHT_DATA      RW, write triggers weight_wr_pulse
//==================================================================
module axi_lite_regs #
(
    parameter ADDR_WIDTH = 5,
    parameter DATA_WIDTH = 32,
    parameter WEIGHT_WIDTH = 8
)
(
    input  wire clk,
    input  wire rst,

    // AXI4-Lite write address / data / response
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                  s_axi_awvalid,
    output reg                   s_axi_awready,
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire                  s_axi_wvalid,
    output reg                   s_axi_wready,
    output reg  [1:0]            s_axi_bresp,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    // AXI4-Lite read address / data
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                  s_axi_arvalid,
    output reg                   s_axi_arready,
    output reg  [DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]            s_axi_rresp,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready,

    // Register <-> FSM interface
    output reg         start_pulse,
    input  wire         done,
    input  wire         busy,
    output reg [15:0]   img_width,
    output reg [15:0]   img_height,
    output reg [31:0]   kernel_base_addr,

    // AXI-Lite controlled weight write interface
    output reg                          weight_wr_pulse,
    output reg [31:0]                   weight_base_addr,
    output reg [3:0]                    weight_index,
    output reg signed [WEIGHT_WIDTH-1:0] weight_data
);

    localparam ADDR_CTRL   = 5'h00;
    localparam ADDR_STATUS = 5'h04;
    localparam ADDR_WIDTH_ = 5'h08;
    localparam ADDR_HEIGHT = 5'h0C;
    localparam ADDR_KBASE  = 5'h10;
    localparam ADDR_WBASE  = 5'h14;
    localparam ADDR_WINDEX = 5'h18;
    localparam ADDR_WDATA  = 5'h1C;

    reg [ADDR_WIDTH-1:0] awaddr_latched;

    // --- Write channel ---
    always @(posedge clk) begin
        if (rst) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            start_pulse   <= 1'b0;
            img_width     <= 16'd0;
            img_height    <= 16'd0;
            kernel_base_addr <= 32'd0;
            weight_wr_pulse <= 1'b0;
            weight_base_addr <= 32'd0;
            weight_index <= 4'd0;
            weight_data <= {WEIGHT_WIDTH{1'b0}};
        end
        else begin
            start_pulse <= 1'b0;
            weight_wr_pulse <= 1'b0;

            if (s_axi_awvalid && s_axi_wvalid && !s_axi_awready) begin
                s_axi_awready  <= 1'b1;
                s_axi_wready   <= 1'b1;
                awaddr_latched <= s_axi_awaddr;
            end
            else begin
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
            end

            if (s_axi_awready && s_axi_wready) begin
                case (awaddr_latched)
                    ADDR_CTRL:   start_pulse      <= s_axi_wdata[0];
                    ADDR_WIDTH_: img_width        <= s_axi_wdata[15:0];
                    ADDR_HEIGHT: img_height       <= s_axi_wdata[15:0];
                    ADDR_KBASE:  kernel_base_addr <= s_axi_wdata;
                    ADDR_WBASE:  weight_base_addr <= s_axi_wdata;
                    ADDR_WINDEX: weight_index     <= s_axi_wdata[3:0];
                    ADDR_WDATA: begin
                        weight_data     <= s_axi_wdata[WEIGHT_WIDTH-1:0];
                        weight_wr_pulse <= 1'b1;
                    end
                    default: ;
                endcase
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
            end
            else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // --- Read channel ---
    always @(posedge clk) begin
        if (rst) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
        end
        else begin
            if (s_axi_arvalid && !s_axi_arready) begin
                s_axi_arready <= 1'b1;
            end
            else begin
                s_axi_arready <= 1'b0;
            end

            if (s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                case (s_axi_araddr)
                    ADDR_CTRL:   s_axi_rdata <= {31'd0, 1'b0};
                    ADDR_STATUS: s_axi_rdata <= {30'd0, busy, done};
                    ADDR_WIDTH_: s_axi_rdata <= {16'd0, img_width};
                    ADDR_HEIGHT: s_axi_rdata <= {16'd0, img_height};
                    ADDR_KBASE:  s_axi_rdata <= kernel_base_addr;
                    ADDR_WBASE:  s_axi_rdata <= weight_base_addr;
                    ADDR_WINDEX: s_axi_rdata <= {28'd0, weight_index};
                    ADDR_WDATA:  s_axi_rdata <= {{(DATA_WIDTH-WEIGHT_WIDTH){weight_data[WEIGHT_WIDTH-1]}}, weight_data};
                    default:     s_axi_rdata <= 32'hDEAD_BEEF;
                endcase
            end
            else if (s_axi_rready && s_axi_rvalid) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
