`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: A. Ashwanth
// 
// Create Date: 24.09.2026 08:14:07
// Design Name: Viterbi Decoder
// Module Name: viterbi_top
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

// Top-level K=3, rate-1/2 Viterbi decoder.
// rx[1:0] in -> BMU -> ACS (pm fed back via pm_register) -> SMU -> decoded_bit
//
// Pipeline latency from rx to decoded_bit: 1 cycle (BMU register) + HIST_DEPTH
// cycles (SMU fill) before decoded_valid asserts.

module viterbi_top #(
    parameter PM_WIDTH   = 16,
    parameter HIST_DEPTH = 20,
    parameter NORM_EN    = 1
)(
    input  clk,
    input  rst_n,
    input  [1:0] rx,
    output decoded_bit,
    output decoded_valid
);
 
    // --- Branch Metric Unit ---
    wire [1:0] bm00, bm01, bm10, bm11;
    Branch_Metric_Unit bmu_i (
        .clk(clk), .rst_n(rst_n),
        .rx(rx),
        .bm00(bm00), .bm01(bm01), .bm10(bm10), .bm11(bm11)
    );
 
    // --- path metric feedback wires ---
    wire [PM_WIDTH-1:0] pm00, pm01, pm10, pm11;            // registered, into ACS
    wire [PM_WIDTH:0]   pm_new00, pm_new01, pm_new10, pm_new11; // ACS output, into pm_register
 
    // --- Add-Compare-Select ---
    wire dec00, dec01, dec10, dec11;
    acs_top #(.PM_WIDTH(PM_WIDTH)) acs_i (
        .clk(clk), .rst_n(rst_n),
        .pm00(pm00), .pm01(pm01), .pm10(pm10), .pm11(pm11),
        .bm00(bm00), .bm01(bm01), .bm10(bm10), .bm11(bm11),
        .pm_out00(pm_new00), .pm_out01(pm_new01), .pm_out10(pm_new10), .pm_out11(pm_new11),
        .dec00(dec00), .dec01(dec01), .dec10(dec10), .dec11(dec11)
    );
 
    // --- Path metric normalization (combinational; acs_u's own register
    // is the sole clocked state element in this feedback loop) ---
    pm_register #(.PM_WIDTH(PM_WIDTH), .NORM_EN(NORM_EN)) pmreg_i (
        .pm_in00(pm_new00), .pm_in01(pm_new01), .pm_in10(pm_new10), .pm_in11(pm_new11),
        .pm00(pm00), .pm01(pm01), .pm10(pm10), .pm11(pm11)
    );
 
    // --- Survivor Memory Unit ---
    smu #(.HIST_DEPTH(HIST_DEPTH), .PM_WIDTH(PM_WIDTH)) smu_i (
        .clk(clk), .rst_n(rst_n),
        .dec00(dec00), .dec01(dec01), .dec10(dec10), .dec11(dec11),
        .pm00(pm00), .pm01(pm01), .pm10(pm10), .pm11(pm11),
        .decoded_bit(decoded_bit),
        .decoded_valid(decoded_valid)
    );
 
endmodule
