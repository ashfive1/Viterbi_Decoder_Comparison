`timescale 1ns/1ps
// K=3 BER testbench.
// Plusargs: +N=<input bits> +OFF=<alignment offset> +IN=<file> +MASK=<file> +OUT=<file> [+MAXFLUSH=<cycles>]
//   IN   : N lines of 0/1 (input bits)
//   MASK : 2N lines of 0/1. Line 2i XORs tx[1] (out0), line 2i+1 XORs tx[0] (out1) of symbol i.
//   OUT  : one line per decoded_valid bit, in the order they appear.
// After the N data symbols, error-free zero symbols are fed (flush) until the decoder has
// emitted at least N+OFF bits (or MAXFLUSH extra cycles pass).
module tb_k3;
    localparam MAXN = 65536;
    integer N, OFF, MAXFLUSH, fd, i, ng;
    reg [8*512-1:0] f_in, f_mask, f_out;
    reg in_mem   [0:MAXN-1];
    reg mask_mem [0:2*MAXN-1];

    reg clk = 0, rst_n = 0;
    reg u = 0;
    reg [1:0] rx = 2'b00, m;
    wire [1:0] tx;
    wire db, dv;

    convolutional_encoder enc (.clk(clk), .rst_n(rst_n), .u(u), .tx(tx));
    viterbi_top           dec (.clk(clk), .rst_n(rst_n), .rx(rx), .decoded_bit(db), .decoded_valid(dv));

    always #5 clk = ~clk;

    initial begin
        if (!$value$plusargs("N=%d", N))              N = 10000;
        if (!$value$plusargs("OFF=%d", OFF))          OFF = 0;
        if (!$value$plusargs("MAXFLUSH=%d", MAXFLUSH)) MAXFLUSH = 2000;
        if (!$value$plusargs("IN=%s", f_in))     begin $display("ERROR: +IN missing");   $finish; end
        if (!$value$plusargs("MASK=%s", f_mask)) begin $display("ERROR: +MASK missing"); $finish; end
        if (!$value$plusargs("OUT=%s", f_out))   begin $display("ERROR: +OUT missing");  $finish; end
        $readmemb(f_in,   in_mem);
        $readmemb(f_mask, mask_mem);
        fd = $fopen(f_out, "w");
        ng = 0; i = 0;
        #22 rst_n = 1;
        while ((i < N || ng < N + OFF) && i < N + MAXFLUSH) begin
            @(negedge clk);
            if (i < N) begin u = in_mem[i]; m = {mask_mem[2*i], mask_mem[2*i+1]}; end
            else       begin u = 1'b0;      m = 2'b00; end
            #1 rx = tx ^ m;
            @(posedge clk); #2;
            if (dv) begin $fdisplay(fd, "%b", db); ng = ng + 1; end
            i = i + 1;
        end
        $fclose(fd);
        $display("RESULT collected=%0d cycles=%0d", ng, i);
        $finish;
    end
endmodule
