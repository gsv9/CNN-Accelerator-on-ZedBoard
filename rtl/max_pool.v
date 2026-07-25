`timescale 1ns / 1ps
//==================================================================
// 2x2 Max Pool, stride 2
// The activation stream arrives one value/cycle, row-major, same
// as every other stage in this pipeline. To pool a 2x2 block we
// need one full row of history, so this uses the same
// row-buffer-in-BRAM trick as line_buffer.v:
//   - even output rows: just store into row_buf
//   - odd output rows: compare incoming value against the stored
//     value from the row above, and pair up columns two at a time
// ASSUMES act_width (activation map width feeding this stage) is
// even. If a layer produces an odd width, pad/crop upstream.
//==================================================================
module max_pool #
(
    parameter DATA_WIDTH = 32,
    parameter MAX_WIDTH  = 1024
)
(
    input  wire clk,
    input  wire rst,
    input  wire frame_start,

    input  wire                         valid_in,
    input  wire signed [DATA_WIDTH-1:0] data_in,
    input  wire [15:0]                  act_width,

    output reg  signed [DATA_WIDTH-1:0] pool_out,
    output reg                          valid_out
);

    reg signed [DATA_WIDTH-1:0] row_buf [0:MAX_WIDTH-1];

    reg [15:0] col_cnt;
    reg        row_toggle;   // 0 = storing row, 1 = pooling row
    reg        col_toggle;   // 0 = first of column pair, 1 = second
    reg signed [DATA_WIDTH-1:0] left_val;

    function signed [DATA_WIDTH-1:0] max2;
        input signed [DATA_WIDTH-1:0] a, b;
        begin
            max2 = (a > b) ? a : b;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            col_cnt    <= 0;
            row_toggle <= 1'b0;
            col_toggle <= 1'b0;
            valid_out  <= 1'b0;
        end
        else if (frame_start) begin
            col_cnt    <= 0;
            row_toggle <= 1'b0;
            col_toggle <= 1'b0;
            valid_out  <= 1'b0;
        end
        else if (valid_in) begin
            if (row_toggle == 1'b0) begin
                row_buf[col_cnt] <= data_in;
                valid_out        <= 1'b0;
            end
            else begin
                if (col_toggle == 1'b0) begin
                    left_val  <= max2(data_in, row_buf[col_cnt]);
                    valid_out <= 1'b0;
                end
                else begin
                    pool_out  <= max2(max2(data_in, row_buf[col_cnt]), left_val);
                    valid_out <= 1'b1;
                end
                col_toggle <= ~col_toggle;
            end

            if (col_cnt == act_width - 1) begin
                col_cnt    <= 0;
                row_toggle <= ~row_toggle;
                col_toggle <= 1'b0;
            end
            else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
        else begin
            valid_out <= 1'b0;
        end
    end

endmodule
