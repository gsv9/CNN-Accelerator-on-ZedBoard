`timescale 1ns / 1ps
//======================================================================
// AXI4-Stream Master
//
// Streams feature map data from the Feature Map Buffer to AXI DMA.
//
// Improvements:
// 1. Registered AXI output data
// 2. Proper AXI VALID/READY handshake
// 3. TLAST generated on final transfer
// 4. Word counter increments only after successful transfer
// 5. Busy indication
//======================================================================

module axi_stream_out #
(
    parameter DATA_WIDTH = 32
)
(
    input  wire clk,
    input  wire rst,

    //------------------------------------------------------------
    // Feature Map Buffer Interface
    //------------------------------------------------------------
    input  wire signed [DATA_WIDTH-1:0] fifo_rd_data,
    input  wire                         fifo_rd_data_valid,
    input  wire                         fifo_empty,
    output wire                         fifo_rd_en,

    //------------------------------------------------------------
    // Frame Control
    //------------------------------------------------------------
    input  wire [31:0] frame_len,
    input  wire        frame_start,

    //------------------------------------------------------------
    // AXI4-Stream Master Interface
    //------------------------------------------------------------
    output reg  [DATA_WIDTH-1:0] m_axis_tdata,
    output reg                   m_axis_tvalid,
    input  wire                  m_axis_tready,
    output reg                   m_axis_tlast,

    //------------------------------------------------------------
    // Status
    //------------------------------------------------------------
    output wire busy
);

    //------------------------------------------------------------
    // Internal Registers
    //------------------------------------------------------------

    reg [31:0] word_cnt;
    reg [31:0] rd_req_cnt;

    assign busy = m_axis_tvalid;

    //------------------------------------------------------------
    // FIFO Read Control
    //------------------------------------------------------------

    assign fifo_rd_en =
            (frame_len != 0) &&
            (rd_req_cnt < frame_len) &&
            !fifo_empty &&
            (!m_axis_tvalid || m_axis_tready);

    //------------------------------------------------------------
    // AXI Stream Logic
    //------------------------------------------------------------

    always @(posedge clk)
    begin

        if(rst)
        begin

            m_axis_tdata  <= 0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            word_cnt      <= 32'd0;
            rd_req_cnt    <= 32'd0;

        end

        else
        begin

            //----------------------------------------------------
            // Start of New Frame
            //----------------------------------------------------

            if(frame_start)
            begin
                word_cnt <= 32'd0;
                rd_req_cnt <= 32'd0;
            end
            else if(fifo_rd_en)
            begin
                rd_req_cnt <= rd_req_cnt + 1'b1;
            end

            //----------------------------------------------------
            // Transfer Completed
            //----------------------------------------------------

            if(m_axis_tvalid && m_axis_tready)
            begin

                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;

                word_cnt <= word_cnt + 1'b1;

            end

            //----------------------------------------------------
            // Load Next FIFO Word
            //----------------------------------------------------

            if(fifo_rd_data_valid &&
              (!m_axis_tvalid || m_axis_tready))
            begin

                m_axis_tdata  <= fifo_rd_data;
                m_axis_tvalid <= 1'b1;

                if(word_cnt == (frame_len - 1))
                    m_axis_tlast <= 1'b1;
                else
                    m_axis_tlast <= 1'b0;

            end

        end

    end

endmodule
