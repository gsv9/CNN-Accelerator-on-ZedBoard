`timescale 1ns / 1ps

module line_buffer #
(
    parameter DATA_WIDTH  = 8,
    parameter MAX_WIDTH   = 1024,
    parameter KERNEL_SIZE = 3
)
(
    input  wire clk,
    input  wire rst,
    input  wire frame_start,
    input  wire frame_end,
    input  wire [15:0] img_width,
    input  wire [15:0] img_height,
    input  wire [DATA_WIDTH-1:0] pixel_in,
    input  wire                  in_valid,
    output wire                  in_ready,
    output wire [DATA_WIDTH-1:0] row0_data,
    output wire [DATA_WIDTH-1:0] row1_data,
    output wire [DATA_WIDTH-1:0] row2_data,
    output reg                   out_valid,
    input wire ds_ready
);

assign in_ready = ds_ready;

reg [DATA_WIDTH-1:0] line0 [0:MAX_WIDTH-1];
reg [DATA_WIDTH-1:0] line1 [0:MAX_WIDTH-1];

reg [15:0] col_cnt;
reg [15:0] row_cnt;
reg [DATA_WIDTH-1:0] current_pixel;
reg [DATA_WIDTH-1:0] line0_read;
reg [DATA_WIDTH-1:0] line1_read;

always @(posedge clk)
begin
    if(rst)
    begin
        col_cnt       <= 0;
        row_cnt       <= 0;
        current_pixel <= 0;
        line0_read    <= 0;
        line1_read    <= 0;
        out_valid     <= 0;
    end
    else
    begin
        if(frame_start)
        begin
            col_cnt       <= 0;
            row_cnt       <= 0;
            out_valid     <= 0;
        end

        out_valid <= 1'b0;

        if(in_valid && ds_ready)
        begin
            current_pixel <= pixel_in;
            line0_read <= line0[col_cnt];
            line1_read <= line1[col_cnt];
            line0[col_cnt] <= pixel_in;
            line1[col_cnt] <= line0[col_cnt];
            out_valid <= (row_cnt >= (KERNEL_SIZE-1));

            if(col_cnt == (img_width - 1))
            begin
                col_cnt <= 0;
                if(row_cnt != (img_height - 1))
                    row_cnt <= row_cnt + 1;
                else
                    row_cnt <= row_cnt;
            end
            else
            begin
                col_cnt <= col_cnt + 1;
            end
        end

        if(frame_end)
        begin
            col_cnt   <= 0;
            row_cnt   <= 0;
            out_valid <= 0;
        end

    end
end

assign row0_data = line1_read;
assign row1_data = line0_read;
assign row2_data = current_pixel;

endmodule
