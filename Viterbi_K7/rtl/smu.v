`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// smu : Survivor Memory Unit, block traceback with RAM
//
//  Decision RAM : M = 4*TB_LEN + MEM_MARGIN words x NS bits, circular.
//                 One word (all NS decision bits) written per step.
//                 Two independent read pointers (dual read port RAM).
//
//  Steps are grouped in blocks of L = TB_LEN.  When block j is complete:
//
//   TB  engine : start at best state (or 0), trace back L steps over block j.
//                (no output - it only lets the survivor paths merge)
//   DEC engine : starts from the state TB ended on (= state at end of block
//                j-1) and traces back L more steps over block j-1.  The MSB
//                of the state at each step is the decoded bit of that step.
//                Skipped for j = 0 (nothing before it).
//   Reorder    : DEC produces bits newest -> oldest.  They are written into a
//                ping-pong pair of L-bit buffers at their block offset, then
//                read out oldest -> newest (decoded_valid high for L cycles).
//
//  Effective traceback depth for every decoded bit is >= L+1 steps.
//  TB(j+1) and DEC(j) run at the same time, which is why the RAM has two read
//  ports.  Blocks complete >= L cycles apart so each engine is always idle
//  when it is triggered again.
//
//  Decision convention (from acs_array): the decision bit stored for state S
//  is the LSB of S's winning predecessor, so   prev = {S[K-3:0], dec[S]}.
//
//  RAM hazard: DEC(j) reads block j's lowest addresses last; block j+4 would
//  overwrite them.  MEM_MARGIN extra words delay that overwrite so a read
//  never races a write (needs MEM_MARGIN >= 3).
//------------------------------------------------------------------------------
module smu #(
    parameter K          = 7,
    parameter TB_LEN     = 42,
    parameter START_BEST = 1,
    parameter MEM_MARGIN = 4,
    parameter NS         = (1 << (K-1))     // do not override
)(
    input               clk,
    input               rst_n,
    input               step,               // one ACS step happening this cycle
    input  [NS-1:0]     dec,                // decisions of that step
    input  [K-2:0]      best_state,         // valid in the cycle after the block's last step
    output reg          decoded_bit,
    output reg          decoded_valid
);
    localparam L  = TB_LEN;
    localparam M  = 4*L + MEM_MARGIN;
    localparam AW = $clog2(M);
    localparam CW = $clog2(L+1);

    function [AW-1:0] a_dec(input [AW-1:0] a);
        a_dec = (a == 0) ? (M-1) : (a - 1);
    endfunction
    function [AW-1:0] a_inc(input [AW-1:0] a);
        a_inc = (a == M-1) ? 0 : (a + 1);
    endfunction

    //--------------------------------------------------------------------------
    // decision RAM + write side
    //--------------------------------------------------------------------------
    reg [NS-1:0] mem [0:M-1];
    reg [AW-1:0] wr_ptr;            // next write address
    reg [CW-1:0] wr_off;            // step offset inside current block
    reg          blk_done;          // 1 cycle after a block's last step

    wire [AW-1:0] last_wr = a_dec(wr_ptr);   // valid while blk_done = 1

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr   <= 0;
            wr_off   <= 0;
            blk_done <= 1'b0;
        end else begin
            blk_done <= 1'b0;
            if (step) begin
                mem[wr_ptr] <= dec;
                wr_ptr      <= a_inc(wr_ptr);
                if (wr_off == L-1) begin
                    wr_off   <= 0;
                    blk_done <= 1'b1;
                end else begin
                    wr_off   <= wr_off + 1'b1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // TB engine (traceback only, no output)
    //   issue stage : present address, RAM data registered one cycle later
    //   consume     : pick decision bit, step the state back
    //--------------------------------------------------------------------------
    reg          tb_issue;
    reg [CW-1:0] tb_icnt;
    reg [AW-1:0] tb_addr;
    reg [AW-1:0] dec_a0;            // address where DEC starts (= TB last addr - 1)
    reg [K-2:0]  tb_start;
    reg          tb_dv, tb_dv_first, tb_dv_last;
    reg [NS-1:0] tb_rdata;
    reg [K-2:0]  tb_state;
    reg          tb_fin;

    wire [K-2:0] tb_cur = tb_dv_first ? tb_start : tb_state;
    wire         tb_sel = tb_rdata[tb_cur];
    wire [K-2:0] tb_nxt = {tb_cur[K-3:0], tb_sel};

    always @(posedge clk) begin
        if (!rst_n) begin
            tb_issue <= 1'b0; tb_icnt <= 0; tb_addr <= 0; dec_a0 <= 0;
            tb_start <= 0; tb_dv <= 1'b0; tb_dv_first <= 1'b0; tb_dv_last <= 1'b0;
            tb_rdata <= 0; tb_state <= 0; tb_fin <= 1'b0;
        end else begin
            tb_fin      <= 1'b0;
            // ---- issue stage
            tb_dv       <= tb_issue;
            tb_dv_first <= tb_issue && (tb_icnt == 0);
            tb_dv_last  <= tb_issue && (tb_icnt == L-1);
            if (tb_issue) begin
                tb_rdata <= mem[tb_addr];
                tb_addr  <= a_dec(tb_addr);
                tb_icnt  <= tb_icnt + 1'b1;
                if (tb_icnt == L-1) begin
                    tb_issue <= 1'b0;
                    dec_a0   <= a_dec(tb_addr);
                end
            end
            // ---- consume stage
            if (tb_dv) begin
                tb_state <= tb_nxt;
                if (tb_dv_last) tb_fin <= 1'b1;
            end
            // ---- (re)trigger: overrides the issue-stage end-of-run above
            if (blk_done) begin
                tb_issue <= 1'b1;
                tb_icnt  <= 0;
                tb_addr  <= last_wr;
                tb_start <= START_BEST ? best_state : {(K-1){1'b0}};
            end
        end
    end

    //--------------------------------------------------------------------------
    // DEC engine (traceback + decode into ping-pong reorder buffers)
    //--------------------------------------------------------------------------
    reg          first_tb_done;
    reg          dec_issue;
    reg [CW-1:0] dec_icnt;
    reg [AW-1:0] dec_addr;
    reg [K-2:0]  dec_start;
    reg          dec_dv, dec_dv_first, dec_dv_last;
    reg [NS-1:0] dec_rdata;
    reg [K-2:0]  dec_state;
    reg [CW-1:0] dec_pos;
    reg          dec_par;
    reg          dec_fin, dec_fin_par;

    reg [L-1:0]  obuf0, obuf1;

    wire [K-2:0] dc_cur = dec_dv_first ? dec_start : dec_state;
    wire         dc_sel = dec_rdata[dc_cur];
    wire [CW-1:0] dc_pos = dec_dv_first ? (L-1) : dec_pos;
    wire          dc_par = dec_dv_first ? ~dec_par : dec_par;

    always @(posedge clk) begin
        if (!rst_n) begin
            first_tb_done <= 1'b0;
            dec_issue <= 1'b0; dec_icnt <= 0; dec_addr <= 0; dec_start <= 0;
            dec_dv <= 1'b0; dec_dv_first <= 1'b0; dec_dv_last <= 1'b0;
            dec_rdata <= 0; dec_state <= 0; dec_pos <= 0; dec_par <= 1'b0;
            dec_fin <= 1'b0; dec_fin_par <= 1'b0;
            obuf0 <= 0; obuf1 <= 0;
        end else begin
            dec_fin      <= 1'b0;
            // ---- issue stage
            dec_dv       <= dec_issue;
            dec_dv_first <= dec_issue && (dec_icnt == 0);
            dec_dv_last  <= dec_issue && (dec_icnt == L-1);
            if (dec_issue) begin
                dec_rdata <= mem[dec_addr];
                dec_addr  <= a_dec(dec_addr);
                dec_icnt  <= dec_icnt + 1'b1;
                if (dec_icnt == L-1) dec_issue <= 1'b0;
            end
            // ---- consume stage: decoded bit = MSB of state *before* stepping back
            if (dec_dv) begin
                dec_state <= {dc_cur[K-3:0], dc_sel};
                dec_pos   <= dc_pos - 1'b1;
                dec_par   <= dc_par;
                if (dc_par) obuf1[dc_pos] <= dc_cur[K-2];
                else        obuf0[dc_pos] <= dc_cur[K-2];
                if (dec_dv_last) begin
                    dec_fin     <= 1'b1;
                    dec_fin_par <= dc_par;
                end
            end
            // ---- trigger when TB finished (but not for the very first block)
            if (tb_fin) begin
                if (!first_tb_done) begin
                    first_tb_done <= 1'b1;
                end else begin
                    dec_issue <= 1'b1;
                    dec_icnt  <= 0;
                    dec_addr  <= dec_a0;
                    dec_start <= tb_state;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // read-out of the finished reorder buffer, oldest bit first
    //--------------------------------------------------------------------------
    reg          ro_act, ro_par;
    reg [CW-1:0] ro_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            ro_act <= 1'b0; ro_par <= 1'b0; ro_cnt <= 0;
            decoded_bit <= 1'b0; decoded_valid <= 1'b0;
        end else begin
            if (ro_act) begin
                decoded_bit   <= ro_par ? obuf1[ro_cnt] : obuf0[ro_cnt];
                decoded_valid <= 1'b1;
                ro_cnt        <= ro_cnt + 1'b1;
                if (ro_cnt == L-1) ro_act <= 1'b0;
            end else begin
                decoded_valid <= 1'b0;
            end
            if (dec_fin) begin                 // overrides end-of-run above
                ro_act <= 1'b1;
                ro_cnt <= 0;
                ro_par <= dec_fin_par;
            end
        end
    end
endmodule
