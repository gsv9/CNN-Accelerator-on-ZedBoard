`timescale 1ns / 1ps
//===============================================================
// Weight BRAM
//
// Dual-port memory.
//
// Port A : Write port (Weight Loader)
// Port B : Read port  (Convolution Engine)
//
// Stores all convolution kernels.
//===============================================================

module weight_bram #
(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10,             // 1024 entries
    parameter DEPTH      = (1<<ADDR_WIDTH)
)
(
    input wire clk,

    //--------------------------------------------------
    // PORT A : Write
    //--------------------------------------------------
    input wire                    wr_en,
    input wire [ADDR_WIDTH-1:0]   wr_addr,
    input wire signed [DATA_WIDTH-1:0] wr_data,

    //--------------------------------------------------
    // PORT B : Read
    //--------------------------------------------------
    input wire [ADDR_WIDTH-1:0]   rd_addr,
    output reg signed [DATA_WIDTH-1:0] rd_data
);

reg signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

always @(posedge clk)
begin

    // Write Port
    if(wr_en)
        mem[wr_addr] <= wr_data;

    // Read Port
    rd_data <= mem[rd_addr];

end

endmodule