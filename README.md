# Viterbi Decoder BER Study: K=3 vs K=7

Measures how two rate-1/2 hard-decision Viterbi decoders (constraint length K=3 and K=7)
hold up as an increasing number of coded bits are flipped. Output: BER vs error density,
plus supporting plots and CSVs.

## Contents
1. [Quick start](#1-quick-start)
2. [Project layout](#2-project-layout)
3. [Background: what was done](#3-background-what-was-done)
4. [Method](#4-method)
5. [Configuration](#5-configuration)
6. [Outputs](#6-outputs)
7. [Reading the results](#7-reading-the-results)
8. [Runtime and troubleshooting](#8-runtime-and-troubleshooting)
9. [Limitations](#9-limitations)

---

## 1. Quick start
Tested on Ubuntu / WSL2.

```bash
sudo apt update && sudo apt install -y iverilog python3 python3-venv
unzip Viterbi_BER_Sweep.zip && cd Viterbi_BER_Sweep
./run_all.sh --quick     # ~10 s smoke test (N=1000, few iterations)
./run_all.sh             # full sweep, then plots
```

- `run_all.sh` checks for `iverilog`, `vvp`, `python3`, then runs the sweep and the plots.
- If `numpy`/`pandas`/`matplotlib` are missing, it builds a local `.venv` and installs
  `requirements.txt` into it (needs internet and `python3-venv`; typically under 2 minutes, first time only).
- Extra arguments go to `sim/run_sweep.py`, e.g. `./run_all.sh --jobs 4`.
- Re-plot without re-simulating: `python3 sim/plot_results.py`

## 2. Project layout
```
Viterbi_K3/rtl/        K=3 RTL (encoder, BMU, ACS, PM normalizer, SMU, top), untouched
Viterbi_K7/rtl/        K=7 RTL (encoder, BMU, ACS array, PM unit, SMU, top), untouched
tb/tb_k3.v             testbench: encoder -> XOR mask -> K3 decoder
tb/tb_k7.v             testbench: encoder -> XOR mask -> K7 decoder
sim/run_sweep.py       config block, stimulus generation, simulation, scoring, CSV output
sim/plot_results.py    reads the CSVs, writes PNG plots
run_all.sh             runs both scripts
requirements.txt       numpy, pandas, matplotlib
results/               created on run: CSVs, run_config.json, plots/
```

## 3. Background: what was done
**Step 1: RTL validation.** The original zip held two Viterbi decoder projects plus 5 reference papers.
- All expected files were present in both (6 RTL files each, no testbenches).
- Both compile cleanly with Icarus Verilog (`-Wall`, no warnings).
- With throwaway testbenches, each decoder's own encoder was fed random bits and the decoder
  output was compared to the input. Result: 0 mismatches clean and with injected errors
  (K3: 400 bits; K7: 600 bits).
- Decoder alignment: K3 outputs are offset by 2 bits (with `decoded_valid`); K7 is aligned at 0.

**Step 2: experiment design.** Agreed with the project owner through a Q&A, summarised in section 4.

**Step 3: tooling.** Testbenches and Python scripts written, smoke-tested in quick mode,
and packaged. The full sweep is run on the user's machine.

## 4. Method
```
fixed input bits -> encoder -> (coded bits XOR error mask) -> decoder -> decoded bits -> compare with input
```

**Terms**
- **Run:** one error density, i.e. a fixed number of flipped bits.
- **Iteration:** a repeat within a run: same flip count, new random flip positions.
- **Error density:** flips / coded bits (coded length = 2N, since the code rate is 1/2).
- **BER:** decoded bits that differ from the input / N.

**Setup**
- N = 10,000 input bits, one fixed random stream for the whole experiment.
- Both decoders get the identical input and the identical mask in every iteration.
- Flip count = round(density x 2N), placed at unique random positions (exact-count model,
  equivalent to a binary symmetric channel; no burst errors).
- After the data, the testbench feeds error-free zero symbols (flush) until the decoder has
  output all N bits. The flush zeros are not scored and not counted in N.
- The mask is applied to the encoder output inside the testbench. Mask line 2i flips `tx[1]`
  (out0) and line 2i+1 flips `tx[0]` (out1) of symbol i.
- Decoding is **hard-decision**: both BMUs take 2 bits per symbol. Soft-decision would need
  a different noise model (e.g. AWGN) and wider metrics in the RTL, so it is out of scope.

**Densities and iterations**

| Densities (% of coded bits) | Iterations per run |
|---|---|
| 0 (sanity run) | 1 |
| 1, 2, 3, 5 | 50 |
| 7, 10, 15, 20, 25, 30, 35, 40, 45, 50 | 20 |

Low densities get more iterations because decoded BER there is tiny (often 0 to a few bits
per 10k), so many samples are needed for a stable average. Errors also arrive in bursts, so
the effective sample size is smaller than the raw bit count.

**Latency and alignment**
Before the sweep, a clean (no-error) run per decoder finds the output alignment offset and the
flush length needed. Nothing is hardcoded. Measured on the supplied RTL:
- K3: offset 2 bits, flush 20 cycles.
- K7: offset 0 bits, flush 174 cycles.

If a clean decode does not match the input, the script stops with an error.

**Reproducibility**
- One master seed (`MASTER_SEED`) derives the input seed and every per-iteration seed.
- Each iteration's seed is logged in `iterations.csv`; the master and input seeds are in `run_config.json`.
- The testbenches use no randomness, so the same seed gives identical results.

**Implementation notes**
- Each testbench is compiled once with `iverilog`, then `vvp` is run per iteration with
  plusargs (`+N`, `+OFF`, `+IN`, `+MASK`, `+OUT`, `+MAXFLUSH`).
- Python and the simulator exchange plain text files (one bit per line); scratch files are deleted afterwards.
- Iterations run in parallel (threads launching `vvp` subprocesses).
- Non-0/1 outputs (x/z) and missing output bits count as errors.

## 5. Configuration
Edit the CONFIG block at the top of `sim/run_sweep.py`:

| Setting | Default | Meaning |
|---|---|---|
| `N_BITS` | 10000 | input bits per iteration |
| `DENSITIES_PCT` | 0,1,2,3,5,7,10,15,20,25,...,50 | error densities, % of coded bits |
| `LOW_TIER_MAX_PCT` | 5 | densities up to this use `ITERS_LOW` |
| `ITERS_LOW` / `ITERS_HIGH` | 50 / 20 | iterations per run |
| `MASTER_SEED` | 20261024 | seeds everything |
| `DECODERS` | K3, K7 | which decoders to run |
| `JOBS` | cores - 1 | parallel simulations |
| `MAX_FLUSH` | 2000 | safety cap on extra cycles |

Command-line overrides: `--quick`, `--n`, `--seed`, `--jobs`, `--decoders`, `--out`.
RTL parameters were left at defaults (K3: `HIST_DEPTH=20`, `PM_WIDTH=16`; K7: `TB_LEN=42`, `PM_WIDTH=8`, `START_PEN=16`, `START_BEST=1`).

## 6. Outputs
All in `results/`.

**`iterations.csv`** (one row per iteration and decoder)
`run_idx, density_pct, n_flips, iteration, seed, decoder, n_input_bits, uncoded_ber, residual_errors, ber, frame_error, n_bursts, mean_burst_len, max_burst_len`

**`summary.csv`** (one row per density and decoder)
- `iterations, total_input_bits, total_errors`
- `mean_ber, std_ber, min_ber, max_ber, ci95_low, ci95_high` (t-based 95% CI)
- `pooled_ber` (total errors / total bits)
- `ber_upper95`: 3 / total bits when zero errors were seen (rule of three)
- `frame_error_rate`: fraction of iterations with at least one residual error
- `mean_n_bursts, mean_burst_len, max_burst_len`: residual error bursts (consecutive wrong bits)
- `uncoded_ber`: channel error rate (flips / 2N)
- `ber_gain`: uncoded / decoded BER; `ber_gain_lower_bound` when zero errors

**`run_config.json`**: settings, seeds, calibration results, elapsed time.

**`plots/`**
- `1_ber_vs_density.png`: BER vs density, log y, 95% CI bars, faint per-iteration dots, uncoded baseline
- `1b_ber_vs_density_low_end_zoom.png`: same, 0 to 15% only
- `2_frame_error_rate.png`
- `3_burst_length.png`
- `4_ber_gain.png`

## 7. Reading the results
- **Hollow markers** mean zero errors were seen; the point is drawn at the 95% upper bound (BER <= 3 / total bits), not at 0.
- **0% density** is excluded from the plots (log axis) but is in the CSVs and must show 0 errors for both decoders.
- **Capacity limit:** for a hard-decision rate-1/2 code, reliable decoding is not possible above about 11% flips.
  Expect both curves to climb toward 0.5 beyond roughly 10 to 15%; that is expected behaviour, not a bug.
- **Where K7 should win:** the low-density region, where its stronger code corrects errors K3 cannot.
- **Errors "fixed" vs "not fixed":** flips are on coded bits and residual errors are on data bits, so they
  cannot be matched one-to-one. Use `uncoded_ber`, `ber`, and `ber_gain` for the comparison.

## 8. Runtime and troubleshooting
**Runtime (measured on a single core, one 10k-bit simulation):**
- K7: about 5 s, K3: about 0.1 s.
- Full sweep: 401 iterations x 2 decoders, roughly 35 min on one core; much less with parallel jobs.
- `--quick` takes about 10 s.

**Troubleshooting**
- `iverilog not found`: `sudo apt install -y iverilog`
- venv creation fails: `sudo apt install -y python3-venv`
- To skip the venv: `sudo apt install -y python3-numpy python3-pandas python3-matplotlib`
- `CALIBRATION FAILED`: the clean decode did not match the input; check the RTL or testbench.
- `WARNING: errors at 0% density`: same cause; results should not be trusted until it is fixed.
- Plots are written with the non-interactive Agg backend, so no display is needed on WSL2.

## 9. Limitations
- Hard-decision only; no soft-decision or AWGN comparison.
- Single fixed input stream and exact-count random flips; no burst-error channel.
- Not covered: back-to-back frames, `rx_valid` gaps on K7, synthesis or timing.
- The decoders' default RTL parameters are used; traceback depth is not swept.
- At low densities, 100k to 500k bits per point may still show only a few errors; use the CI and upper-bound columns when judging those points.