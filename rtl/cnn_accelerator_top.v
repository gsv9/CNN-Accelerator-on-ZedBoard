`timescale 1ns / 1ps
//======================================================================
// cnn_accelerator_top.v
//
// Top-level integration of the single-conv-layer accelerator. Invoked
// once per network layer by the PS: software writes IMG_WIDTH,
// IMG_HEIGHT, KERNEL_BASE_ADDR via AXI-Lite, ensures the weights for
// this layer are already in weight_bram, then pulses START. DMA
// streams the layer's input feature map in over AXI-Stream and reads
// the pooled output feature map back out over AXI-Stream. Software
// loops this call once per conv layer of the backbone.
//
// KNOWN GAPS (see chat notes):
//   - conv_engine.bias tied to 0 -- no bias storage/loading path exists
//     yet in weight_cache/weight_loader/weight_bram.
//   - Backpressure only reaches back to sliding_window/line_buffer via
//     feature_map_buffer.full; conv_engine/leaky_relu/max_pool cannot
//     themselves stall (no ready ports on those modules).
//   - Weight upload is available through AXI-Lite registers. The
//     ext_weight_wr_* ports remain as an optional direct hardware path.
//======================================================================

// =====================================================================
// PART 1 -- Module declaration, parameters, ports, internal signals
// =====================================================================
module cnn_accelerator_top #
(
    parameter PIX_WIDTH     = 8,    // input pixel / feature width
    parameter WEIGHT_WIDTH  = 8,
    parameter ACC_WIDTH     = 32,   // conv accumulator / activation width downstream
    parameter KERNEL_SIZE   = 3,
    parameter W_ADDR_WIDTH  = 10,   // weight_bram address width (1024 entries)
    parameter LB_MAX_WIDTH  = 1024, // line_buffer max row length
    parameter FIFO_DEPTH    = 2048, // feature_map_buffer depth
    parameter AXI_ADDR_W    = 5,    // axi_lite_regs address width
    parameter AXI_DATA_W    = 32
)
(
    input  wire clk,
    input  wire rst,

    //------------------------------------------------------------
    // AXI4-Lite control/status (-> axi_lite_regs)
    //------------------------------------------------------------
    input  wire [AXI_ADDR_W-1:0] s_axi_awaddr,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire [AXI_DATA_W-1:0] s_axi_wdata,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,
    input  wire [AXI_ADDR_W-1:0] s_axi_araddr,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    output wire [AXI_DATA_W-1:0] s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready,

    //------------------------------------------------------------
    // AXI4-Stream slave -- input feature map, from AXI DMA MM2S
    //------------------------------------------------------------
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    //------------------------------------------------------------
    // AXI4-Stream master -- output feature map, to AXI DMA S2MM
    //------------------------------------------------------------
    output wire [ACC_WIDTH-1:0] m_axis_tdata,
    output wire                 m_axis_tvalid,
    input  wire                 m_axis_tready,
    output wire                 m_axis_tlast,

    //------------------------------------------------------------
    // External weight-write port (placeholder -- upload path TBD)
    //------------------------------------------------------------
    input  wire                          ext_weight_wr_en,
    input  wire signed [WEIGHT_WIDTH-1:0] ext_weight_wr_data,
    input  wire [W_ADDR_WIDTH-1:0]       ext_weight_wr_base_addr,
    input  wire [3:0]                    ext_weight_wr_index
);

    // ---- FSM state encoding ----
    localparam S_IDLE    = 3'd0,
               S_LOAD_W  = 3'd1,
               S_RUN     = 3'd2,
               S_DRAIN   = 3'd3,
               S_DONE    = 3'd4;

    reg [2:0]  state;
    reg        done;
    wire       busy = (state != S_IDLE);

    // ---- axi_lite_regs <-> FSM ----
    wire        start_pulse;
    wire [15:0] img_width;
    wire [15:0] img_height;
    wire [31:0] kernel_base_addr;
    wire        axi_weight_wr_pulse;
    wire [31:0] axi_weight_base_addr;
    wire [3:0]  axi_weight_index;
    wire signed [WEIGHT_WIDTH-1:0] axi_weight_data;

    reg  [15:0] cur_img_width;
    reg  [15:0] cur_img_height;
    reg  [31:0] cur_kernel_base;   // latched at START so the FSM's own address
                                    // stepping can't be corrupted by a software
                                    // write mid-load

    // Derived geometry for this layer (valid-only 3x3 conv, then 2x2 pool)
    wire [15:0] conv_width   = cur_img_width  - (KERNEL_SIZE - 1);
    wire [15:0] conv_height  = cur_img_height - (KERNEL_SIZE - 1);
    wire [15:0] pooled_width  = conv_width  >> 1;
    wire [15:0] pooled_height = conv_height >> 1;
    wire [31:0] frame_len     = pooled_width * pooled_height;

    // ---- pipeline control pulses ----
    reg  frame_start_pulse;
    reg  frame_end_pulse;

    // ---- backpressure: only real stall point is the output FIFO ----
    wire fmb_full;
    wire pipe_ready = ~fmb_full;

    // ---- axi_stream_slave -> line_buffer signal names (corrected lb_row*) ----
    wire [PIX_WIDTH-1:0] slave_pixel_out;
    wire                 slave_pixel_valid;
    wire                 slave_pixel_last;
    wire                 lb_in_ready;

    wire [PIX_WIDTH-1:0] lb_row0_data, lb_row1_data, lb_row2_data;
    wire                 lb_out_valid;

    // ---- sliding_window outputs ----
    wire [PIX_WIDTH-1:0] sw_P00, sw_P01, sw_P02;
    wire [PIX_WIDTH-1:0] sw_P10, sw_P11, sw_P12;
    wire [PIX_WIDTH-1:0] sw_P20, sw_P21, sw_P22;
    wire                 sw_window_valid;
    wire                 sw_us_ready;

    // ---- weight_cache -> conv_engine ----
    wire                          wc_load;
    wire                          wc_cache_ready;
    wire [W_ADDR_WIDTH-1:0]      wc_bram_rd_addr;
    wire signed [WEIGHT_WIDTH-1:0] wc_bram_rd_data;
    wire signed [WEIGHT_WIDTH-1:0] W00, W01, W02, W10, W11, W12, W20, W21, W22;

    // ---- weight_bram write side (from weight_loader) ----
    wire                          wl_bram_wr_en;
    wire [W_ADDR_WIDTH-1:0]      wl_bram_wr_addr;
    wire signed [WEIGHT_WIDTH-1:0] wl_bram_wr_data;
    wire                          weight_load_enable;
    wire [W_ADDR_WIDTH-1:0]       weight_load_base_addr;
    wire [3:0]                    weight_load_index;
    wire signed [WEIGHT_WIDTH-1:0] weight_load_data;

    // ---- conv_engine -> leaky_relu -> max_pool ----
    wire signed [ACC_WIDTH-1:0] conv_out;
    wire                        conv_valid;
    wire signed [ACC_WIDTH-1:0] relu_out;
    wire                        relu_valid;
    wire signed [ACC_WIDTH-1:0] pool_out;
    wire                        pool_valid;

    // ---- feature_map_buffer <-> axi_stream_out ----
    wire signed [ACC_WIDTH-1:0] fmb_rd_data;
    wire                        fmb_empty;
    wire                        fmb_rd_data_valid;
    wire                        fifo_rd_en;
    wire                        output_last_hs;
    reg                         output_done_seen;

    assign weight_load_enable    = ext_weight_wr_en || axi_weight_wr_pulse;
    assign weight_load_base_addr = ext_weight_wr_en ? ext_weight_wr_base_addr : axi_weight_base_addr[W_ADDR_WIDTH-1:0];
    assign weight_load_index     = ext_weight_wr_en ? ext_weight_wr_index     : axi_weight_index;
    assign weight_load_data      = ext_weight_wr_en ? ext_weight_wr_data      : axi_weight_data;

// =====================================================================
// PART 2 -- axi_stream_slave, weight_loader, weight_bram, weight_cache
// =====================================================================

    axi_lite_regs #(
        .ADDR_WIDTH(AXI_ADDR_W),
        .DATA_WIDTH(AXI_DATA_W),
        .WEIGHT_WIDTH(WEIGHT_WIDTH)
    ) u_axi_lite_regs (
        .clk              (clk),
        .rst              (rst),
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),
        .start_pulse      (start_pulse),
        .done             (done),
        .busy             (busy),
        .img_width        (img_width),
        .img_height       (img_height),
        .kernel_base_addr (kernel_base_addr),
        .weight_wr_pulse  (axi_weight_wr_pulse),
        .weight_base_addr (axi_weight_base_addr),
        .weight_index     (axi_weight_index),
        .weight_data      (axi_weight_data)
    );

    axi_stream_slave #(
        .DATA_WIDTH(PIX_WIDTH)
    ) u_axi_stream_slave (
        .clk            (clk),
        .rst            (rst),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .pixel_out      (slave_pixel_out),
        .pixel_valid    (slave_pixel_valid),
        .pixel_last     (slave_pixel_last),
        .pipeline_ready (lb_in_ready)
    );

    weight_loader #(
        .DATA_WIDTH(WEIGHT_WIDTH),
        .ADDR_WIDTH(W_ADDR_WIDTH)
    ) u_weight_loader (
        .clk          (clk),
        .rst          (rst),
        .load_enable  (weight_load_enable),
        .weight_in    (weight_load_data),
        .base_addr    (weight_load_base_addr),
        .weight_index (weight_load_index),
        .bram_wr_en   (wl_bram_wr_en),
        .bram_wr_addr (wl_bram_wr_addr),
        .bram_wr_data (wl_bram_wr_data)
    );

    weight_bram #(
        .DATA_WIDTH(WEIGHT_WIDTH),
        .ADDR_WIDTH(W_ADDR_WIDTH)
    ) u_weight_bram (
        .clk     (clk),
        .wr_en   (wl_bram_wr_en),
        .wr_addr (wl_bram_wr_addr),
        .wr_data (wl_bram_wr_data),
        .rd_addr (wc_bram_rd_addr),
        .rd_data (wc_bram_rd_data)
    );

    weight_cache #(
        .DATA_WIDTH(WEIGHT_WIDTH),
        .ADDR_WIDTH(W_ADDR_WIDTH)
    ) u_weight_cache (
        .clk          (clk),
        .rst          (rst),
        .load         (wc_load),
        .base_addr    (cur_kernel_base[W_ADDR_WIDTH-1:0]), // latched, truncated to cache addr width
        .bram_rd_addr (wc_bram_rd_addr),
        .bram_rd_data (wc_bram_rd_data),
        .cache_ready  (wc_cache_ready),
        .W00(W00), .W01(W01), .W02(W02),
        .W10(W10), .W11(W11), .W12(W12),
        .W20(W20), .W21(W21), .W22(W22)
    );

// =====================================================================
// PART 3 -- line_buffer, sliding_window, conv_engine, leaky_relu, max_pool
// =====================================================================

    line_buffer #(
        .DATA_WIDTH  (PIX_WIDTH),
        .MAX_WIDTH   (LB_MAX_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE)
    ) u_line_buffer (
        .clk         (clk),
        .rst         (rst),
        .frame_start (frame_start_pulse),
        .frame_end   (frame_end_pulse),
        .img_width   (cur_img_width),
        .img_height  (cur_img_height),
        .pixel_in    (slave_pixel_out),
        .in_valid    (slave_pixel_valid),
        .in_ready    (lb_in_ready),
        .row0_data   (lb_row0_data),
        .row1_data   (lb_row1_data),
        .row2_data   (lb_row2_data),
        .out_valid   (lb_out_valid),
        .ds_ready    (pipe_ready)
    );

    sliding_window #(
        .DATA_WIDTH  (PIX_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE)
    ) u_sliding_window (
        .clk          (clk),
        .rst          (rst),
        .frame_start  (frame_start_pulse),
        .img_width    (cur_img_width),
        .row0_data    (lb_row0_data),
        .row1_data    (lb_row1_data),
        .row2_data    (lb_row2_data),
        .valid_in     (lb_out_valid),
        .ds_ready     (pipe_ready),
        .us_ready     (sw_us_ready),
        .P00(sw_P00), .P01(sw_P01), .P02(sw_P02),
        .P10(sw_P10), .P11(sw_P11), .P12(sw_P12),
        .P20(sw_P20), .P21(sw_P21), .P22(sw_P22),
        .window_valid (sw_window_valid)
    );

    conv_engine #(
        .DATA_WIDTH   (PIX_WIDTH),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .ACC_WIDTH    (ACC_WIDTH)
    ) u_conv_engine (
        .clk       (clk),
        .rst       (rst),
        .valid_in  (sw_window_valid),
        .P00(sw_P00), .P01(sw_P01), .P02(sw_P02),
        .P10(sw_P10), .P11(sw_P11), .P12(sw_P12),
        .P20(sw_P20), .P21(sw_P21), .P22(sw_P22),
        .W00(W00), .W01(W01), .W02(W02),
        .W10(W10), .W11(W11), .W12(W12),
        .W20(W20), .W21(W21), .W22(W22),
        .bias      ({ACC_WIDTH{1'b0}}),   // TODO: no bias storage/loading path yet
        .conv_out  (conv_out),
        .valid_out (conv_valid)
    );

    leaky_relu #(
        .DATA_WIDTH  (ACC_WIDTH),
        .ALPHA_SHIFT (3)
    ) u_leaky_relu (
        .clk       (clk),
        .rst       (rst),
        .valid_in  (conv_valid),
        .data_in   (conv_out),
        .data_out  (relu_out),
        .valid_out (relu_valid)
    );

    max_pool #(
        .DATA_WIDTH (ACC_WIDTH),
        .MAX_WIDTH  (LB_MAX_WIDTH)
    ) u_max_pool (
        .clk         (clk),
        .rst         (rst),
        .frame_start (frame_start_pulse),
        .valid_in    (relu_valid),
        .data_in     (relu_out),
        .act_width   (conv_width),
        .pool_out    (pool_out),
        .valid_out   (pool_valid)
    );

// =====================================================================
// PART 4 -- feature_map_buffer, axi_stream_out, frame-length calc,
//           FSM, busy/done, endmodule
// =====================================================================

    feature_map_buffer #(
        .DATA_WIDTH (ACC_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) u_feature_map_buffer (
        .clk           (clk),
        .rst           (rst),
        .wr_en         (pool_valid),
        .wr_data       (pool_out),
        .full          (fmb_full),
        .rd_en         (fifo_rd_en),
        .rd_data       (fmb_rd_data),
        .empty         (fmb_empty),
        .rd_data_valid (fmb_rd_data_valid)
    );

    axi_stream_out #(
        .DATA_WIDTH (ACC_WIDTH)
    ) u_axi_stream_out (
        .clk                 (clk),
        .rst                 (rst),
        .fifo_rd_data        (fmb_rd_data),
        .fifo_rd_data_valid  (fmb_rd_data_valid),
        .fifo_empty          (fmb_empty),
        .fifo_rd_en          (fifo_rd_en),
        .frame_len           (frame_len),
        .frame_start         (frame_start_pulse),
        .m_axis_tdata        (m_axis_tdata),
        .m_axis_tvalid       (m_axis_tvalid),
        .m_axis_tready       (m_axis_tready),
        .m_axis_tlast        (m_axis_tlast)
    );

    // weight_cache.load: pulse exactly one cycle, the same cycle START
    // is accepted out of IDLE.
    assign wc_load = (state == S_IDLE) && start_pulse;
    assign output_last_hs = m_axis_tvalid && m_axis_tready && m_axis_tlast;

    // ---- Top-level FSM: one call = one conv layer ----
    always @(posedge clk) begin
        if (rst) begin
            state             <= S_IDLE;
            done              <= 1'b0;
            frame_start_pulse <= 1'b0;
            frame_end_pulse   <= 1'b0;
            cur_img_width     <= 16'd0;
            cur_img_height    <= 16'd0;
            cur_kernel_base   <= 32'd0;
            output_done_seen  <= 1'b0;
        end
        else begin
            // default-deassert one-cycle pulses every clock
            frame_start_pulse <= 1'b0;
            frame_end_pulse   <= 1'b0;

            if (output_last_hs)
                output_done_seen <= 1'b1;

            case (state)

                S_IDLE: begin
                    if (start_pulse) begin
                        cur_img_width   <= img_width;
                        cur_img_height  <= img_height;
                        cur_kernel_base <= kernel_base_addr;
                        done            <= 1'b0;
                        output_done_seen <= 1'b0;
                        state           <= S_LOAD_W;
                    end
                end

                // Wait for weight_cache to finish fetching this layer's
                // 3x3 kernel from weight_bram before streaming pixels.
                S_LOAD_W: begin
                    if (wc_cache_ready) begin
                        frame_start_pulse <= 1'b1;  // primes line_buffer + max_pool
                        state             <= S_RUN;
                    end
                end

                // Pixels flow continuously via axi_stream_slave while
                // pipe_ready allows it. Watch for the DMA's tlast
                // (propagated as slave_pixel_last) to know the whole
                // input frame has been accepted.
                S_RUN: begin
                    if (slave_pixel_valid && slave_pixel_last) begin
                        frame_end_pulse <= 1'b1;   // lets line_buffer reset for next call
                        state           <= (output_done_seen || output_last_hs) ? S_DONE : S_DRAIN;
                    end
                end

                // Let the fixed-latency pipeline (conv -> relu -> pool)
                // finish flushing through the FIFO and out the AXI-Stream
                // master before declaring done.
                S_DRAIN: begin
                    if (output_done_seen || output_last_hs) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
