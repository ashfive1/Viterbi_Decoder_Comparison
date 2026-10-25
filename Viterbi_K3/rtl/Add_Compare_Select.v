`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: A Ashwanth
// 
// Create Date: 26.08.2026 09:44:25
// Design Name: Viterbi Decoder
// Module Name: acs_u
// Project Name: 
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

module acs_top #(
        parameter PM_WIDTH = 16
    )(
        input clk,
        input rst_n,
        input [PM_WIDTH-1:0] pm00, pm01, pm10, pm11,
        input [1:0] bm00, bm01, bm10, bm11,
        output [PM_WIDTH:0] pm_out00, pm_out01, pm_out10, pm_out11,
        output dec00, dec01, dec10, dec11
    );
    acs_u #(.PM_WIDTH(PM_WIDTH)) u00 (.clk(clk), .rst_n(rst_n),
               .pm_prev_1(pm00), .pm_prev_2(pm01),
               .bm_1(bm00), .bm_2(bm11),
               .pm_out(pm_out00),
               .decision(dec00)
         );
 
    acs_u #(.PM_WIDTH(PM_WIDTH)) u01 (.clk(clk), .rst_n(rst_n),
               .pm_prev_1(pm10), .pm_prev_2(pm11),
               .bm_1(bm10), .bm_2(bm01),
               .pm_out(pm_out01),
               .decision(dec01)
         );
 
    acs_u #(.PM_WIDTH(PM_WIDTH)) u10 (.clk(clk), .rst_n(rst_n),
               .pm_prev_1(pm00), .pm_prev_2(pm01),
               .bm_1(bm11), .bm_2(bm00),
               .pm_out(pm_out10),
               .decision(dec10)
         );
 
    acs_u #(.PM_WIDTH(PM_WIDTH)) u11 (.clk(clk), .rst_n(rst_n),
               .pm_prev_1(pm10), .pm_prev_2(pm11),
               .bm_1(bm01), .bm_2(bm10),
               .pm_out(pm_out11),
               .decision(dec11)
         );
 
endmodule
 
module acs_u #(
        parameter PM_WIDTH = 16
    )(
    input clk,
    input rst_n,
    input [PM_WIDTH-1:0] pm_prev_1,
    input [PM_WIDTH-1:0] pm_prev_2,
    input [1:0] bm_1,
    input [1:0] bm_2,
    output reg [PM_WIDTH:0] pm_out,
    output decision
    );
 
    wire [PM_WIDTH:0] pm_out_1 = pm_prev_1 + bm_1;
    wire [PM_WIDTH:0] pm_out_2 = pm_prev_2 + bm_2;
 
    // decision = 1 means predecessor_1 (pm_prev_1/bm_1) won -- this convention
    // is reused directly by the SMU's predecessor-selection muxing.
    assign decision = (pm_out_1) < (pm_out_2);
 
    always @(posedge clk) begin
        if (rst_n) begin
            if (decision) begin
                pm_out <= pm_out_1;
            end
            else begin
                pm_out <= pm_out_2;
            end
        end
        else begin
            pm_out <= 0;
        end
    end
endmodule