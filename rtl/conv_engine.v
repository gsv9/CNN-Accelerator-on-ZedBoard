`timescale 1ns / 1ps
//==================================================================
// 3x3 Convolution Engine
// 9 multipliers + adder tree + bias add, 1-cycle pipeline latency.
// Weights/bias are configurable inputs (loaded by FSM per layer).
// Pixels are unsigned (raw feature-map data), weights/bias are
// signed fixed-point.
//==================================================================
module conv_engine #
(
    parameter DATA_WIDTH   = 8,
    parameter WEIGHT_WIDTH = 8,
    parameter ACC_WIDTH    = 32
)
(
    input  wire clk,
    input  wire rst,

    input  wire valid_in,
    input  wire [DATA_WIDTH-1:0] P00, P01, P02,
    input  wire [DATA_WIDTH-1:0] P10, P11, P12,
    input  wire [DATA_WIDTH-1:0] P20, P21, P22,

    input  wire signed [WEIGHT_WIDTH-1:0] W00, W01, W02,
    input  wire signed [WEIGHT_WIDTH-1:0] W10, W11, W12,
    input  wire signed [WEIGHT_WIDTH-1:0] W20, W21, W22,
    input  wire signed [ACC_WIDTH-1:0]    bias,

    output reg  signed [ACC_WIDTH-1:0] conv_out,
    output reg                         valid_out
);

    localparam MUL_WIDTH = DATA_WIDTH + WEIGHT_WIDTH + 1;

    wire signed [MUL_WIDTH-1:0] m00, m01, m02;
    wire signed [MUL_WIDTH-1:0] m10, m11, m12;
    wire signed [MUL_WIDTH-1:0] m20, m21, m22;

    // zero-extend unsigned pixel by 1 bit before signed multiply
    assign m00 = $signed({1'b0, P00}) * W00;
    assign m01 = $signed({1'b0, P01}) * W01;
    assign m02 = $signed({1'b0, P02}) * W02;
    assign m10 = $signed({1'b0, P10}) * W10;
    assign m11 = $signed({1'b0, P11}) * W11;
    assign m12 = $signed({1'b0, P12}) * W12;
    assign m20 = $signed({1'b0, P20}) * W20;
    assign m21 = $signed({1'b0, P21}) * W21;
    assign m22 = $signed({1'b0, P22}) * W22;

    // adder tree
    wire signed [MUL_WIDTH:0]   s0 = m00 + m01;
    wire signed [MUL_WIDTH:0]   s1 = m02 + m10;
    wire signed [MUL_WIDTH:0]   s2 = m11 + m12;
    wire signed [MUL_WIDTH:0]   s3 = m20 + m21;
    wire signed [MUL_WIDTH+1:0] s4 = s0 + s1;
    wire signed [MUL_WIDTH+1:0] s5 = s2 + s3;
    wire signed [MUL_WIDTH+2:0] s6 = s4 + s5;
    wire signed [MUL_WIDTH+2:0] s7 = s6 + m22;

    wire signed [ACC_WIDTH-1:0] sum_with_bias = s7 + bias;

    always @(posedge clk) begin
        if (rst) begin
            conv_out  <= {ACC_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end
        else begin
            conv_out  <= sum_with_bias;
            valid_out <= valid_in;
        end
    end

endmodule
