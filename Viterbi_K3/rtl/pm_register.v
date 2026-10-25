`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: A. Ashwanth
// 
// Create Date: 24.09.2026 08:10:32
// Design Name: Viterbi Decoder
// Module Name: pm_register
// Project Name: ConvEncVitDec
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

module pm_register #(
    parameter PM_WIDTH = 16,     // width of normalized/fed-back path metrics
    parameter NORM_EN  = 1       // 1 = subtract global min, 0 = pass through
)(
    input  [PM_WIDTH:0] pm_in00, pm_in01, pm_in10, pm_in11,   // new path metrics from acs_top
    output [PM_WIDTH-1:0] pm00, pm01, pm10, pm11               // normalized, fed back into acs_top
);
 
    // global minimum across all 4 candidate path metrics (for normalization)
    wire [PM_WIDTH:0] min_a  = (pm_in00 < pm_in01) ? pm_in00 : pm_in01;
    wire [PM_WIDTH:0] min_b  = (pm_in10 < pm_in11) ? pm_in10 : pm_in11;
    wire [PM_WIDTH:0] pm_min = (min_a < min_b) ? min_a : min_b;
 
    assign pm00 = NORM_EN ? (pm_in00 - pm_min) : pm_in00[PM_WIDTH-1:0];
    assign pm01 = NORM_EN ? (pm_in01 - pm_min) : pm_in01[PM_WIDTH-1:0];
    assign pm10 = NORM_EN ? (pm_in10 - pm_min) : pm_in10[PM_WIDTH-1:0];
    assign pm11 = NORM_EN ? (pm_in11 - pm_min) : pm_in11[PM_WIDTH-1:0];
 
endmodule
