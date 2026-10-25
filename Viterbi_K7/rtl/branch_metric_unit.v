`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// branch_metric_unit : hard-decision Hamming distances
//
//  bm[2*s +: 2] = hamming(rx, s)   for candidate symbols s = 00,01,10,11
//  Registered (1-cycle latency). valid_out marks a "step" for the ACS stage.
//------------------------------------------------------------------------------
module branch_metric_unit (
    input        clk,
    input        rst_n,
    input        valid_in,
    input  [1:0] rx,
    output reg [7:0] bm,          // {bm11, bm10, bm01, bm00}
    output reg       valid_out
);
    // (rx[1]^a) + (rx[0]^b) for candidate {a,b}
    wire [1:0] bm00 = {1'b0, rx[1]       } + {1'b0, rx[0]       };
    wire [1:0] bm01 = {1'b0, rx[1]       } + {1'b0, ~rx[0]      };
    wire [1:0] bm10 = {1'b0, ~rx[1]      } + {1'b0, rx[0]       };
    wire [1:0] bm11 = {1'b0, ~rx[1]      } + {1'b0, ~rx[0]      };

    always @(posedge clk) begin
        if (!rst_n) begin
            bm        <= 8'd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in)
                bm <= {bm11, bm10, bm01, bm00};
        end
    end
endmodule
