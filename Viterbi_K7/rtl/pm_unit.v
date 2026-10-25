`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// pm_unit : path-metric registers + best-state finder
//
//  * Reset: state 0 = 0, every other state = START_PEN (encoder starts in 0).
//  * No normalisation logic: metrics wrap (modulo arithmetic), see acs_array.
//  * best_state (combinational) = argmin over all states, tournament tree,
//    lower index wins ties.  Only built when START_BEST=1; it is sampled by the
//    SMU once per block, so it can be treated as a multicycle path if needed.
//------------------------------------------------------------------------------
module pm_unit #(
    parameter K          = 7,
    parameter PM_WIDTH   = 8,
    parameter START_PEN  = 16,
    parameter START_BEST = 1,
    parameter NS         = (1 << (K-1))     // do not override
)(
    input                     clk,
    input                     rst_n,
    input                     step_en,
    input  [NS*PM_WIDTH-1:0]  pm_next,
    output [NS*PM_WIDTH-1:0]  pm,
    output [K-2:0]            best_state
);
    localparam [PM_WIDTH-1:0] PEN = START_PEN;

    reg [NS*PM_WIDTH-1:0] pm_q;
    assign pm = pm_q;

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < NS; i = i + 1)
                pm_q[i*PM_WIDTH +: PM_WIDTH] <= (i == 0) ? {PM_WIDTH{1'b0}} : PEN;
        end else if (step_en) begin
            pm_q <= pm_next;
        end
    end

    generate
        if (START_BEST) begin : g_best
            // heap-ordered tournament: leaves NS..2NS-1, root = 1, children 2i,2i+1
            wire [PM_WIDTH-1:0] hv [1:2*NS-1];
            wire [K-2:0]        hi [1:2*NS-1];
            genvar j, h;
            for (j = 0; j < NS; j = j + 1) begin : g_leaf
                assign hv[NS+j] = pm_q[j*PM_WIDTH +: PM_WIDTH];
                assign hi[NS+j] = j;
            end
            for (h = 1; h < NS; h = h + 1) begin : g_node
                wire [PM_WIDTH-1:0] dd = hv[2*h+1] - hv[2*h];
                wire pick_r = dd[PM_WIDTH-1];          // right strictly smaller
                assign hv[h] = pick_r ? hv[2*h+1] : hv[2*h];
                assign hi[h] = pick_r ? hi[2*h+1] : hi[2*h];
            end
            assign best_state = hi[1];
        end else begin : g_nobest
            assign best_state = {(K-1){1'b0}};
        end
    endgenerate
endmodule
