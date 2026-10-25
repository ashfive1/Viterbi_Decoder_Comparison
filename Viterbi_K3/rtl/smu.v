`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: A. Ashwanth
// 
// Create Date: 24.09.2026 08:11:48
// Design Name: Viterbi Decoder
// Module Name: smu
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

module smu #(
    parameter HIST_DEPTH = 20,
    parameter PM_WIDTH   = 16
)(
    input  clk,
    input  rst_n,
    input  dec00, dec01, dec10, dec11,            // from acs_top
    input  [PM_WIDTH-1:0] pm00, pm01, pm10, pm11, // registered path metrics (for argmin)
    output decoded_bit,
    output decoded_valid
);
 
    reg [HIST_DEPTH-1:0] hist00, hist01, hist10, hist11;
    reg [$clog2(HIST_DEPTH+1)-1:0] fill_cnt;
 
    // select which predecessor's history to extend -- same pairing as acs_top
    wire [HIST_DEPTH-1:0] sel_hist00 = dec00 ? hist00 : hist01;
    wire [HIST_DEPTH-1:0] sel_hist01 = dec01 ? hist10 : hist11;
    wire [HIST_DEPTH-1:0] sel_hist10 = dec10 ? hist00 : hist01;
    wire [HIST_DEPTH-1:0] sel_hist11 = dec11 ? hist10 : hist11;
 
    // bit appended on reaching each state = that state's own MSB (see header)
    localparam APPEND00 = 1'b0;
    localparam APPEND01 = 1'b0;
    localparam APPEND10 = 1'b1;
    localparam APPEND11 = 1'b1;
 
    always @(posedge clk) begin
        if (!rst_n) begin
            hist00 <= 0; hist01 <= 0; hist10 <= 0; hist11 <= 0;
            fill_cnt <= 0;
        end
        else begin
            // shift left, drop oldest (MSB), append new decision bit at LSB
            hist00 <= {sel_hist00[HIST_DEPTH-2:0], APPEND00};
            hist01 <= {sel_hist01[HIST_DEPTH-2:0], APPEND01};
            hist10 <= {sel_hist10[HIST_DEPTH-2:0], APPEND10};
            hist11 <= {sel_hist11[HIST_DEPTH-2:0], APPEND11};
 
            if (fill_cnt < HIST_DEPTH)
                fill_cnt <= fill_cnt + 1'b1;
        end
    end
 
    // --- argmin over the 4 path metrics: pick which state's history to output ---
    wire pm_a_min          = (pm00 <= pm01);
    wire [PM_WIDTH-1:0] pm_min_a = pm_a_min ? pm00 : pm01;
 
    wire pm_b_min          = (pm10 <= pm11);
    wire [PM_WIDTH-1:0] pm_min_b = pm_b_min ? pm10 : pm11;
 
    wire final_min_is_a = (pm_min_a <= pm_min_b);
 
    wire [HIST_DEPTH-1:0] hist_min =
        final_min_is_a ? (pm_a_min ? hist00 : hist01)
                        : (pm_b_min ? hist10 : hist11);
 
    assign decoded_bit   = hist_min[HIST_DEPTH-1];   // oldest bit = decoded output
    assign decoded_valid = (fill_cnt == HIST_DEPTH);
 
endmodule
