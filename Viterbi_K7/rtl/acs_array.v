`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// acs_array : 2^(K-1) add-compare-select units (purely combinational)
//
// For next-state n the two predecessors are P0={n[K-3:0],0}, P1={n[K-3:0],1}.
// The branch P->n carries symbol f({n,b}) = {^(w&G0), ^(w&G1)},  w={n,b}.
//
//   cand0 = pm[P0] + bm[sym(n,0)]      cand1 = pm[P1] + bm[sym(n,1)]
//   dec[n]     = 1 iff cand1 < cand0   (strict -> ties go to P0)
//                == LSB of the winning predecessor state
//   pm_next[n] = min(cand0, cand1)
//
// Metrics wrap modulo 2^PM_WIDTH; "<" is the sign bit of the difference.
// This is safe because the spread between any two live metrics is bounded by
// 2*(K-1) (+ start penalty), far below 2^(PM_WIDTH-1).
//------------------------------------------------------------------------------
module acs_array #(
    parameter K        = 7,
    parameter PM_WIDTH = 8,
    parameter [K-1:0] G0 = 7'o171,
    parameter [K-1:0] G1 = 7'o133,
    parameter NS       = (1 << (K-1))      // do not override
)(
    input  [NS*PM_WIDTH-1:0] pm,           // current metrics, state i at [i*W +: W]
    input  [7:0]             bm,           // branch metrics {bm11,bm10,bm01,bm00}
    output [NS*PM_WIDTH-1:0] pm_next,
    output [NS-1:0]          dec
);
    genvar n;
    generate
        for (n = 0; n < NS; n = n + 1) begin : g_acs
            localparam [K-2:0] N  = n;
            localparam [K-1:0] W0 = {N, 1'b0};
            localparam [K-1:0] W1 = {N, 1'b1};
            localparam [1:0] SYM0 = {^(W0 & G0), ^(W0 & G1)};
            localparam [1:0] SYM1 = {^(W1 & G0), ^(W1 & G1)};
            localparam integer P0 = (n % (NS/2)) * 2;
            localparam integer P1 = P0 + 1;

            wire [PM_WIDTH-1:0] pm0 = pm[P0*PM_WIDTH +: PM_WIDTH];
            wire [PM_WIDTH-1:0] pm1 = pm[P1*PM_WIDTH +: PM_WIDTH];
            wire [1:0] bm0 = bm[SYM0*2 +: 2];
            wire [1:0] bm1 = bm[SYM1*2 +: 2];

            wire [PM_WIDTH-1:0] c0   = pm0 + bm0;
            wire [PM_WIDTH-1:0] c1   = pm1 + bm1;
            wire [PM_WIDTH-1:0] diff = c1 - c0;

            assign dec[n] = diff[PM_WIDTH-1];
            assign pm_next[n*PM_WIDTH +: PM_WIDTH] = dec[n] ? c1 : c0;
        end
    endgenerate
endmodule
