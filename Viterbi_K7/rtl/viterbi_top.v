`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// viterbi_top : K=7, rate-1/2 (171,133) hard-decision Viterbi decoder
//
//   rx/rx_valid -> BMU -> ACS array <-> PM registers -> SMU (traceback RAM)
//
//  * one 2-bit symbol per rx_valid cycle, gaps (rx_valid=0) are allowed
//  * decoded_valid is high for TB_LEN consecutive cycles per block; output
//    appears after roughly 3-4 * TB_LEN cycles of input (traceback latency)
//  * to flush the last bits, keep feeding (zero-input) symbols
//------------------------------------------------------------------------------
module viterbi_top #(
    parameter PM_WIDTH   = 8,
    parameter TB_LEN     = 42,      // block / traceback length (>= 5*K recommended)
    parameter START_PEN  = 16,      // initial metric of states != 0
    parameter START_BEST = 1,       // 1: trace from best state, 0: from state 0
    parameter MEM_MARGIN = 4
)(
    input        clk,
    input        rst_n,
    input        rx_valid,
    input  [1:0] rx,
    output       decoded_bit,
    output       decoded_valid
);
    localparam K  = 7;
    localparam NS = 64;

    // modulo metric arithmetic needs 2^(PM_WIDTH-1) > max(2*(K-1), START_PEN) + 2
    initial begin
        if ((1 << (PM_WIDTH-1)) <= ((START_PEN > 2*(K-1) ? START_PEN : 2*(K-1)) + 2)) begin
            $display("viterbi_top ERROR: PM_WIDTH=%0d too small for START_PEN=%0d", PM_WIDTH, START_PEN);
            $finish;
        end
    end

    wire [7:0]            bm;
    wire                  step;
    wire [NS*PM_WIDTH-1:0] pm, pm_next;
    wire [NS-1:0]         dec;
    wire [K-2:0]          best_state;

    branch_metric_unit bmu_i (
        .clk(clk), .rst_n(rst_n),
        .valid_in(rx_valid), .rx(rx),
        .bm(bm), .valid_out(step)
    );

    acs_array #(.K(K), .PM_WIDTH(PM_WIDTH)) acs_i (
        .pm(pm), .bm(bm), .pm_next(pm_next), .dec(dec)
    );

    pm_unit #(.K(K), .PM_WIDTH(PM_WIDTH), .START_PEN(START_PEN),
              .START_BEST(START_BEST)) pmu_i (
        .clk(clk), .rst_n(rst_n), .step_en(step),
        .pm_next(pm_next), .pm(pm), .best_state(best_state)
    );

    smu #(.K(K), .TB_LEN(TB_LEN), .START_BEST(START_BEST),
          .MEM_MARGIN(MEM_MARGIN)) smu_i (
        .clk(clk), .rst_n(rst_n),
        .step(step), .dec(dec), .best_state(best_state),
        .decoded_bit(decoded_bit), .decoded_valid(decoded_valid)
    );
endmodule
