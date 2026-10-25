`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: A. Ashwanth
// 
// Create Date: 25.08.2026 23:03:43
// Design Name: Viterbi Decoder
// Module Name: Branch_Metric_Unit
// Project Name: ConvEnv_VitDec
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module Branch_Metric_Unit(
    input clk,
    input rst_n,
    input [1:0] rx,
    output reg [1:0] bm00,
    output reg [1:0] bm01,
    output reg [1:0] bm10,
    output reg [1:0] bm11
    );
    
    always @(posedge clk) begin
        if (rst_n) begin
            bm00 <= (rx[1]^0) + (rx[0]^0);
            bm01 <= (rx[1]^0) + (rx[0]^1);
            bm10 <= (rx[1]^1) + (rx[0]^0);
            bm11 <= (rx[1]^1) + (rx[0]^1);
        end
        else begin
            bm00 <= 0;
            bm01 <= 0;
            bm10 <= 0;
            bm11 <= 0;
        end
    end   
endmodule
