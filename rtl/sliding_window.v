`timescale 1ns / 1ps
//==================================================================
// Sliding Window Generator
// Takes 1 pixel/cycle from each of the 3 line-buffer row outputs
// and builds a 3x3 window using per-row shift registers.
// window_valid asserts once KERNEL_SIZE-1 columns have been shifted
// in (i.e. the window is fully populated).
//==================================================================
module sliding_window #
(
    parameter DATA_WIDTH  = 8,
    parameter KERNEL_SIZE = 3
)
(
    input  wire clk,
    input  wire rst,
    input  wire frame_start,
    input  wire [15:0] img_width,

    input  wire [DATA_WIDTH-1:0] row0_data,
    input  wire [DATA_WIDTH-1:0] row1_data,
    input  wire [DATA_WIDTH-1:0] row2_data,
    input  wire                  valid_in,

    input  wire ds_ready,
    output wire us_ready,

    output wire [DATA_WIDTH-1:0] P00, P01, P02,
    output wire [DATA_WIDTH-1:0] P10, P11, P12,
    output wire [DATA_WIDTH-1:0] P20, P21, P22,

    output reg  window_valid
);

    assign us_ready = ds_ready;

    // shift[0] = newest sample, shift[KERNEL_SIZE-1] = oldest
    reg [DATA_WIDTH-1:0] row0_shift [0:KERNEL_SIZE-1];
    reg [DATA_WIDTH-1:0] row1_shift [0:KERNEL_SIZE-1];
    reg [DATA_WIDTH-1:0] row2_shift [0:KERNEL_SIZE-1];

    reg [$clog2(KERNEL_SIZE):0] col_valid_cnt;
    reg [15:0] col_cnt;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
                row0_shift[i] <= {DATA_WIDTH{1'b0}};
                row1_shift[i] <= {DATA_WIDTH{1'b0}};
                row2_shift[i] <= {DATA_WIDTH{1'b0}};
            end
            col_valid_cnt <= 0;
            col_cnt       <= 0;
            window_valid  <= 1'b0;
        end
        else if (frame_start) begin
            col_valid_cnt <= 0;
            col_cnt       <= 0;
            window_valid  <= 1'b0;
        end
        else if (valid_in && ds_ready) begin
            for (i = KERNEL_SIZE-1; i > 0; i = i - 1) begin
                row0_shift[i] <= row0_shift[i-1];
                row1_shift[i] <= row1_shift[i-1];
                row2_shift[i] <= row2_shift[i-1];
            end
            row0_shift[0] <= row0_data;
            row1_shift[0] <= row1_data;
            row2_shift[0] <= row2_data;

            if (col_valid_cnt < (KERNEL_SIZE-1))
                col_valid_cnt <= col_valid_cnt + 1'b1;

            window_valid <= (col_cnt >= (KERNEL_SIZE-1));

            if (col_cnt == (img_width - 1)) begin
                col_cnt       <= 0;
                col_valid_cnt <= 0;
            end
            else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
        else begin
            window_valid <= 1'b0;
        end
    end

    // oldest sample -> left of window, newest -> right of window
    assign P00 = row0_shift[2]; assign P01 = row0_shift[1]; assign P02 = row0_shift[0];
    assign P10 = row1_shift[2]; assign P11 = row1_shift[1]; assign P12 = row1_shift[0];
    assign P20 = row2_shift[2]; assign P21 = row2_shift[1]; assign P22 = row2_shift[0];

endmodule
