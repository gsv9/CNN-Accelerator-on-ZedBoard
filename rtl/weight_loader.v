`timescale 1ns / 1ps
//==============================================================
// Weight Loader
//
// Writes incoming kernel weights into Weight BRAM.
//
// One weight is written per clock.
//
// Can later be connected to:
//   - AXI-Lite
//   - AXI DMA
//   - AXI Stream
//==============================================================

module weight_loader #
(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10
)
(
    input wire clk,
    input wire rst,

    //----------------------------
    // Weight input
    //----------------------------
    input wire load_enable,

    input wire signed [DATA_WIDTH-1:0] weight_in,

    input wire [ADDR_WIDTH-1:0] base_addr,

    input wire [3:0] weight_index,

    //----------------------------
    // BRAM Interface
    //----------------------------
    output reg bram_wr_en,

    output reg [ADDR_WIDTH-1:0] bram_wr_addr,

    output reg signed [DATA_WIDTH-1:0] bram_wr_data
);

always @(posedge clk)
begin

    if(rst)
    begin
        bram_wr_en   <= 1'b0;
        bram_wr_addr <= 0;
        bram_wr_data <= 0;
    end

    else
    begin

        bram_wr_en <= 1'b0;

        if(load_enable)
        begin

            bram_wr_en   <= 1'b1;

            bram_wr_addr <= base_addr + weight_index;

            bram_wr_data <= weight_in;

        end

    end

end

endmodule