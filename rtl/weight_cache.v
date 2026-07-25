`timescale 1ns / 1ps
//======================================================================
// Weight Cache (corrected for synchronous BRAM read latency)
//
// weight_bram registers rd_data <= mem[rd_addr] -- one clock of
// latency between presenting an address and the data being valid.
// This version issues the NEXT address one cycle ahead of capturing
// the CURRENT one, so every W00..W22 register gets the correct
// address's data instead of being shifted by one.
//
// Sequence (addr issued this cycle -> data captured next cycle):
//   cycle 0: issue addr(base+0)
//   cycle 1: issue addr(base+1), capture W00 = data(base+0)
//   cycle 2: issue addr(base+2), capture W01 = data(base+1)
//   ...
//   cycle 8: (addr held)        , capture W21 = data(base+7)
//   cycle 9: cache_ready         , capture W22 = data(base+8)
//======================================================================

module weight_cache #
(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10
)
(
    input wire clk,
    input wire rst,

    //------------------------------------------------------------
    // Control
    //------------------------------------------------------------
    input wire load,
    input wire [ADDR_WIDTH-1:0] base_addr,

    //------------------------------------------------------------
    // BRAM Read Interface
    //------------------------------------------------------------
    output reg [ADDR_WIDTH-1:0] bram_rd_addr,
    input wire signed [DATA_WIDTH-1:0] bram_rd_data,

    //------------------------------------------------------------
    // Status
    //------------------------------------------------------------
    output reg cache_ready,

    //------------------------------------------------------------
    // Outputs to Convolution Engine
    //------------------------------------------------------------
    output reg signed [DATA_WIDTH-1:0] W00,
    output reg signed [DATA_WIDTH-1:0] W01,
    output reg signed [DATA_WIDTH-1:0] W02,

    output reg signed [DATA_WIDTH-1:0] W10,
    output reg signed [DATA_WIDTH-1:0] W11,
    output reg signed [DATA_WIDTH-1:0] W12,

    output reg signed [DATA_WIDTH-1:0] W20,
    output reg signed [DATA_WIDTH-1:0] W21,
    output reg signed [DATA_WIDTH-1:0] W22
);

    reg [3:0] addr_idx;   // index (0..8) of the weight whose address is on
                          // bram_rd_addr THIS cycle
    reg [3:0] cap_idx;    // index (0..8) of the weight whose data is valid
                          // on bram_rd_data THIS cycle (trails addr_idx by 1)
    reg       cap_valid;  // qualifies cap_idx / bram_rd_data as meaningful
    reg       loading;

    always @(posedge clk) begin
        if (rst) begin
            W00 <= 0; W01 <= 0; W02 <= 0;
            W10 <= 0; W11 <= 0; W12 <= 0;
            W20 <= 0; W21 <= 0; W22 <= 0;

            bram_rd_addr <= 0;
            addr_idx     <= 0;
            cap_idx      <= 0;
            cap_valid    <= 1'b0;
            loading      <= 1'b0;
            cache_ready  <= 1'b0;
        end
        else begin

            // Default: cache_ready is a one-cycle pulse, not a sticky level.
            cache_ready <= 1'b0;

            if (load && !loading) begin
                // Issue the address for weight 0. Nothing is valid to
                // capture yet -- that arrives one cycle from now.
                loading      <= 1'b1;
                addr_idx     <= 4'd0;
                bram_rd_addr <= base_addr;
                cap_valid    <= 1'b0;
            end
            else if (loading) begin

                // Capture the weight whose address we issued last cycle
                if (cap_valid) begin
                    case (cap_idx)
                        4'd0: W00 <= bram_rd_data;
                        4'd1: W01 <= bram_rd_data;
                        4'd2: W02 <= bram_rd_data;
                        4'd3: W10 <= bram_rd_data;
                        4'd4: W11 <= bram_rd_data;
                        4'd5: W12 <= bram_rd_data;
                        4'd6: W20 <= bram_rd_data;
                        4'd7: W21 <= bram_rd_data;
                        4'd8: W22 <= bram_rd_data;
                        default: ;
                    endcase
                end

                // Advance the pipeline: today's issued address becomes
                // next cycle's capture index.
                cap_idx   <= addr_idx;
                cap_valid <= 1'b1;

                if (addr_idx < 4'd8) begin
                    addr_idx     <= addr_idx + 1'b1;
                    bram_rd_addr <= base_addr + addr_idx + 1'b1;
                end
                // else: hold bram_rd_addr at base_addr+8, nothing left to issue

                // Done once we've captured index 8 (W22)
                if (cap_valid && (cap_idx == 4'd8)) begin
                    loading     <= 1'b0;
                    cache_ready <= 1'b1;
                    cap_valid   <= 1'b0;   // tidy: don't leave stale valid asserted
                    addr_idx    <= 4'd0;   // tidy: reset for next load
                    cap_idx     <= 4'd0;
                end
            end

        end
    end

endmodule