`timescale 1ns / 1ps
//==================================================================
// Leaky ReLU
// y = x            , x >= 0
// y = alpha * x     , x < 0
// alpha implemented as a power-of-two right shift (arithmetic, so
// sign-extends correctly) to avoid a multiplier. ALPHA_SHIFT = 3
// gives alpha = 1/8 = 0.125, close to the common Tiny-YOLO default
// of 0.1. Swap in a real multiply if you need an exact 0.1.
//==================================================================
module leaky_relu #
(
    parameter DATA_WIDTH  = 32,
    parameter ALPHA_SHIFT = 3
)
(
    input  wire clk,
    input  wire rst,

    input  wire                         valid_in,
    input  wire signed [DATA_WIDTH-1:0] data_in,

    output reg  signed [DATA_WIDTH-1:0] data_out,
    output reg                          valid_out
);

    wire signed [DATA_WIDTH-1:0] leaky_val = data_in >>> ALPHA_SHIFT;

    always @(posedge clk) begin
        if (rst) begin
            data_out  <= {DATA_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end
        else begin
            valid_out <= valid_in;
            if (data_in[DATA_WIDTH-1] == 1'b0)
                data_out <= data_in;
            else
                data_out <= leaky_val;
        end
    end

endmodule
