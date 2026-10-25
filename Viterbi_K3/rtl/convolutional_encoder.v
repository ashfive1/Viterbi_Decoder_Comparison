`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: A. Ashawanth
// 
// Create Date: 24.09.2026 08:17:06
// Design Name: Viterbi Decoder
// Module Name: convolutional_encoder
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

module convolutional_encoder(
    input  clk,
    input  rst_n,
    input  u,           // input bit, one per clock
    output [1:0] tx      // tx[1]=out0, tx[0]=out1 -- see bit-order note above
);
    reg s1, s0;
 
    wire out0 = u ^ s1 ^ s0;
    wire out1 = u ^ s0;
 
    assign tx = {out0, out1};
 
    always @(posedge clk) begin
        if (!rst_n) begin
            s1 <= 1'b0;
            s0 <= 1'b0;
        end
        else begin
            s1 <= u;
            s0 <= s1;
        end
    end
 
endmodule
