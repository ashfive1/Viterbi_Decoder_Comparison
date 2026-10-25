`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// conv_encoder : rate-1/2 convolutional encoder, K=7, G0=171o, G1=133o
//
//  window w = {u, sr}  (7 bits), sr[5] = previous input, sr[0] = oldest input
//  out0 = ^(w & G0)    out1 = ^(w & G1)       tx = {out0, out1}
//
//  tx is combinational from (u, sr); the shift register advances when en=1.
//------------------------------------------------------------------------------
module conv_encoder #(
    parameter K  = 7,
    parameter [K-1:0] G0 = 7'o171,
    parameter [K-1:0] G1 = 7'o133
)(
    input        clk,
    input        rst_n,
    input        en,        // advance one step (one input bit consumed)
    input        u,         // input bit
    output [1:0] tx         // {out0, out1}
);
    reg  [K-2:0] sr;
    wire [K-1:0] w = {u, sr};

    assign tx = {^(w & G0), ^(w & G1)};

    always @(posedge clk) begin
        if (!rst_n)  sr <= {(K-1){1'b0}};
        else if (en) sr <= {u, sr[K-2:1]};
    end
endmodule
