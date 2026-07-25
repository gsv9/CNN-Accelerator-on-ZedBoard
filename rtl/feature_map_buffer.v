`timescale 1ns / 1ps
//==================================================================
// Feature Map Buffer
// Simple synchronous FIFO (BRAM-inferred) sitting between the
// max-pool output and the AXI-Stream output interface. Write side
// runs on the compute pipeline's valid_out; read side is drained
// by the AXI-Stream master whenever it has data and downstream is
// ready.
//==================================================================
module feature_map_buffer #
(
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 2048,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)
(
    input  wire clk,
    input  wire rst,

    // write side
    input  wire                         wr_en,
    input  wire signed [DATA_WIDTH-1:0] wr_data,
    output wire                         full,

    // read side
    input  wire                          rd_en,
    output reg  signed [DATA_WIDTH-1:0]  rd_data,
    output wire                          empty,
    output reg                           rd_data_valid
);

    reg signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0]   count;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr        <= 0;
            rd_ptr        <= 0;
            count         <= 0;
            rd_data_valid <= 1'b0;
        end
        else begin
            rd_data_valid <= 1'b0;

            if (wr_en && !full) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end

            if (rd_en && !empty) begin
                rd_data       <= mem[rd_ptr];
                rd_ptr        <= rd_ptr + 1'b1;
                rd_data_valid <= 1'b1;
            end

            case ({(wr_en && !full), (rd_en && !empty)})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
