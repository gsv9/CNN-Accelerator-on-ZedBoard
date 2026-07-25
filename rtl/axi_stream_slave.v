`timescale 1ns / 1ps
//==============================================================
// AXI4-Stream Slave
//
// Receives pixels from AXI DMA.
//
// Converts AXI Stream into simple pixel stream.
//
//==============================================================

module axi_stream_slave #
(
    parameter DATA_WIDTH = 8
)
(
    input wire clk,
    input wire rst,

    //---------------------------------------------------
    // AXI Stream Slave Interface
    //---------------------------------------------------

    input wire [31:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,

    //---------------------------------------------------
    // CNN Pipeline Interface
    //---------------------------------------------------

    output reg [DATA_WIDTH-1:0] pixel_out,

    output reg pixel_valid,

    output reg pixel_last,

    input wire pipeline_ready
);

assign s_axis_tready = pipeline_ready;

always @(posedge clk)
begin

    if(rst)
    begin

        pixel_out   <= 0;
        pixel_valid <= 1'b0;
        pixel_last  <= 1'b0;

    end

    else
    begin

        pixel_valid <= 1'b0;
        pixel_last  <= 1'b0;

        if(s_axis_tvalid && pipeline_ready)
        begin

            pixel_out <= s_axis_tdata[DATA_WIDTH-1:0];

            pixel_valid <= 1'b1;

            pixel_last <= s_axis_tlast;

        end

    end

end

endmodule