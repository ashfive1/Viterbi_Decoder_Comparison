#!/usr/bin/env python3
"""
Viterbi K=3 vs K=7 BER sweep.

Flow per iteration:
  fixed input bits --(encoder, in the TB)--> coded bits --XOR error mask--> decoder --> decoded bits
Both decoders get the SAME input bits and the SAME mask in every iteration.

Outputs (in results/):
  iterations.csv   one row per (iteration, decoder)
  summary.csv      one row per (density, decoder)
  run_config.json  config, seeds, calibration (latency/alignment)
Plot with:  python3 sim/plot_results.py
"""
import argparse, glob, json, math, os, re, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import pandas as pd

# ============================== CONFIG ==============================
N_BITS           = 10_000                 # input bits per iteration (flush zeros NOT counted)
DENSITIES_PCT    = [0, 1, 2, 3, 5, 7, 10, 15, 20, 25, 30, 35, 40, 45, 50]
                                          # % of CODED bits flipped (mask length = 2*N_BITS)
LOW_TIER_MAX_PCT = 5                      # runs with density <= this use ITERS_LOW
ITERS_LOW        = 50                     # iterations per run, low densities (BER is tiny -> more samples)
ITERS_HIGH       = 20                     # iterations per run, high densities
MASTER_SEED      = 20261024               # everything else is derived from this
DECODERS         = ["K3", "K7"]           # any subset of K3, K7
IVERILOG         = "iverilog"
VVP              = "vvp"
JOBS             = max(1, (os.cpu_count() or 2) - 1)   # parallel simulations
MAX_FLUSH        = 2000                   # safety cap on extra cycles after the data
CALIB_EXTRA      = 64                     # calibration collects N+this bits to find alignment
QUICK = dict(N_BITS=1000, DENSITIES_PCT=[0, 2, 5, 10, 20, 50], ITERS_LOW=3, ITERS_HIGH=2)
# ====================================================================

ROOT = Path(__file__).resolve().parent.parent
DESIGNS = {
    "K3": dict(tb=ROOT / "tb" / "tb_k3.v", rtl=ROOT / "Viterbi_K3" / "rtl"),
    "K7": dict(tb=ROOT / "tb" / "tb_k7.v", rtl=ROOT / "Viterbi_K7" / "rtl"),
}

T95 = {1:12.706,2:4.303,3:3.182,4:2.776,5:2.571,6:2.447,7:2.365,8:2.306,9:2.262,10:2.228,
       11:2.201,12:2.179,13:2.160,14:2.145,15:2.131,16:2.120,17:2.110,18:2.101,19:2.093,
       20:2.086,21:2.080,22:2.074,23:2.069,24:2.064,25:2.060,26:2.056,27:2.052,28:2.048,
       29:2.045,30:2.042}


def tcrit(df_):
    return T95.get(df_, 1.96) if df_ >= 1 else float("nan")


def write_bits(path, bits):
    Path(path).write_text("\n".join(str(int(b)) for b in bits) + "\n")


def read_bits(path):
    """decoded bits -> int8 array; anything that is not 0/1 (x/z) becomes 2 (counts as an error)."""
    out = []
    for line in Path(path).read_text().split():
        out.append(0 if line == "0" else 1 if line == "1" else 2)
    return np.array(out, dtype=np.int8)


def compile_design(name, build_dir):
    d = DESIGNS[name]
    out = build_dir / f"{name.lower()}.vvp"
    srcs = sorted(glob.glob(str(d["rtl"] / "*.v")))
    cmd = [IVERILOG, "-g2012", "-o", str(out), str(d["tb"])] + srcs
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"[{name}] iverilog compile failed:\n{r.stdout}\n{r.stderr}")
    return out


def run_sim(vvp_file, n, off, in_path, mask_path, out_path):
    cmd = [VVP, str(vvp_file), f"+N={n}", f"+OFF={off}", f"+MAXFLUSH={MAX_FLUSH}",
           f"+IN={in_path}", f"+MASK={mask_path}", f"+OUT={out_path}"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    m = re.search(r"RESULT collected=(\d+) cycles=(\d+)", r.stdout)
    if r.returncode != 0 or not m:
        raise RuntimeError(f"simulation failed ({' '.join(cmd)}):\n{r.stdout}\n{r.stderr}")
    return read_bits(out_path), int(m.group(1)), int(m.group(2))


def score(decoded, inp, off):
    n = len(inp)
    seg = decoded[off:off + n]
    if len(seg) < n:                                   # decoder never produced enough bits
        seg = np.concatenate([seg, np.full(n - len(seg), 2, dtype=np.int8)])
    err = (seg != inp).astype(np.int8)
    total = int(err.sum())
    d = np.diff(np.concatenate(([0], err, [0])))
    starts, ends = np.where(d == 1)[0], np.where(d == -1)[0]
    lens = ends - starts
    return dict(residual_errors=total,
                ber=total / n,
                frame_error=int(total > 0),
                n_bursts=int(len(lens)),
                mean_burst_len=float(lens.mean()) if len(lens) else 0.0,
                max_burst_len=int(lens.max()) if len(lens) else 0)


def calibrate(name, vvp_file, inp, work):
    """Clean (no-error) run: find the output alignment offset and the flush cycles needed."""
    n = len(inp)
    in_p, mask_p, out_p = work / "in.txt", work / f"mask0_{name}.txt", work / f"cal_{name}.txt"
    write_bits(mask_p, np.zeros(2 * n, dtype=np.uint8))
    dec, _, _ = run_sim(vvp_file, n, CALIB_EXTRA, in_p, mask_p, out_p)
    off = next((o for o in range(CALIB_EXTRA + 1)
                if len(dec) >= o + n and np.array_equal(dec[o:o + n], inp)), None)
    if off is None:
        sys.exit(f"[{name}] CALIBRATION FAILED: clean decode does not match input at any "
                 f"offset 0..{CALIB_EXTRA}. Check RTL/testbench.")
    _, collected, cycles = run_sim(vvp_file, n, off, in_p, mask_p, out_p)
    cal = dict(align_offset=off, flush_cycles=cycles - n, collected=collected)
    print(f"[{name}] calibration OK: output offset = {off} bit(s), "
          f"flush needed = {cycles - n} cycles after the last input bit")
    return cal


def iteration_task(ctx, run_idx, pct, n_flips, it_idx):
    n = ctx["n"]
    ss = np.random.SeedSequence([MASTER_SEED, 1, run_idx, it_idx])
    seed = int(ss.generate_state(1)[0])
    rng = np.random.default_rng(seed)
    mask = np.zeros(2 * n, dtype=np.uint8)
    if n_flips:
        mask[rng.choice(2 * n, size=n_flips, replace=False)] = 1
    tag = f"r{run_idx}_i{it_idx}"
    work = ctx["work"]
    mask_p = work / f"mask_{tag}.txt"
    write_bits(mask_p, mask)
    rows, tmp = [], [mask_p]
    try:
        for name in ctx["decoders"]:
            out_p = work / f"out_{name}_{tag}.txt"
            tmp.append(out_p)
            dec, _, _ = run_sim(ctx["vvp"][name], n, ctx["cal"][name]["align_offset"],
                                work / "in.txt", mask_p, out_p)
            row = dict(run_idx=run_idx, density_pct=pct, n_flips=n_flips, iteration=it_idx,
                       seed=seed, decoder=name, n_input_bits=n, uncoded_ber=n_flips / (2 * n))
            row.update(score(dec, ctx["inp"], ctx["cal"][name]["align_offset"]))
            rows.append(row)
    finally:
        for p in tmp:
            try: p.unlink()
            except OSError: pass
    return rows


def summarize(df):
    rows = []
    for (pct, dec), g in df.groupby(["density_pct", "decoder"], sort=True):
        k = len(g)
        bits = int(g.n_input_bits.sum())
        errs = int(g.residual_errors.sum())
        mean = float(g.ber.mean())
        std = float(g.ber.std(ddof=1)) if k > 1 else float("nan")
        half = tcrit(k - 1) * std / math.sqrt(k) if k > 1 else float("nan")
        bursts = int(g.n_bursts.sum())
        unc = float(g.uncoded_ber.iloc[0])
        pooled = errs / bits
        rows.append(dict(
            density_pct=pct, decoder=dec, n_flips=int(g.n_flips.iloc[0]), iterations=k,
            total_input_bits=bits, total_errors=errs,
            mean_ber=mean, std_ber=std, min_ber=float(g.ber.min()), max_ber=float(g.ber.max()),
            ci95_low=max(0.0, mean - half) if k > 1 else float("nan"),
            ci95_high=mean + half if k > 1 else float("nan"),
            pooled_ber=pooled,
            ber_upper95=(3.0 / bits) if errs == 0 else float("nan"),   # rule of three
            frame_error_rate=float(g.frame_error.mean()),
            mean_n_bursts=float(g.n_bursts.mean()),
            mean_burst_len=(errs / bursts) if bursts else 0.0,
            max_burst_len=int(g.max_burst_len.max()),
            uncoded_ber=unc,
            ber_gain=(unc / pooled) if pooled > 0 else float("nan"),
            ber_gain_lower_bound=(unc / (3.0 / bits)) if errs == 0 and unc > 0 else float("nan"),
        ))
    return pd.DataFrame(rows)


def main():
    global N_BITS, DENSITIES_PCT, ITERS_LOW, ITERS_HIGH, MASTER_SEED, DECODERS, JOBS
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--quick", action="store_true", help="small/fast settings for a smoke test")
    ap.add_argument("--n", type=int, help="override N_BITS")
    ap.add_argument("--seed", type=int, help="override MASTER_SEED")
    ap.add_argument("--jobs", type=int, help="parallel simulations")
    ap.add_argument("--decoders", nargs="+", choices=list(DESIGNS), help="subset of decoders")
    ap.add_argument("--out", default=str(ROOT / "results"), help="results directory")
    a = ap.parse_args()
    if a.quick:
        N_BITS, DENSITIES_PCT = QUICK["N_BITS"], QUICK["DENSITIES_PCT"]
        ITERS_LOW, ITERS_HIGH = QUICK["ITERS_LOW"], QUICK["ITERS_HIGH"]
    if a.n: N_BITS = a.n
    if a.seed is not None: MASTER_SEED = a.seed
    if a.jobs: JOBS = a.jobs
    if a.decoders: DECODERS = a.decoders

    out_dir = Path(a.out); work = out_dir / "work"; build = out_dir / "build"
    work.mkdir(parents=True, exist_ok=True); build.mkdir(parents=True, exist_ok=True)

    # fixed input stream
    in_seed = int(np.random.SeedSequence([MASTER_SEED, 0]).generate_state(1)[0])
    inp = np.random.default_rng(in_seed).integers(0, 2, N_BITS, dtype=np.int8)
    write_bits(work / "in.txt", inp)

    print(f"Compiling {', '.join(DECODERS)} ...")
    vvp = {d: compile_design(d, build) for d in DECODERS}
    cal = {d: calibrate(d, vvp[d], inp, work) for d in DECODERS}

    ctx = dict(n=N_BITS, work=work, inp=inp, vvp=vvp, cal=cal, decoders=DECODERS)
    iters_csv = out_dir / "iterations.csv"
    if iters_csv.exists(): iters_csv.unlink()
    first = True
    t0 = time.time()
    for run_idx, pct in enumerate(DENSITIES_PCT):
        n_flips = int(round(pct / 100.0 * 2 * N_BITS))
        n_it = 1 if pct == 0 else (ITERS_LOW if pct <= LOW_TIER_MAX_PCT else ITERS_HIGH)
        with ThreadPoolExecutor(max_workers=JOBS) as ex:
            futs = [ex.submit(iteration_task, ctx, run_idx, pct, n_flips, i) for i in range(n_it)]
            rows = [r for f in futs for r in f.result()]
        rdf = pd.DataFrame(rows)
        rdf.to_csv(iters_csv, mode="a", header=first, index=False); first = False
        msg = ", ".join(f"{d}: BER={rdf[rdf.decoder == d].ber.mean():.2e}" for d in DECODERS)
        print(f"[run {run_idx + 1}/{len(DENSITIES_PCT)}] {pct:>2}% ({n_flips} flips, {n_it} iters)  "
              f"{msg}   [{time.time() - t0:.0f}s]", flush=True)

    df = pd.read_csv(iters_csv)
    summary = summarize(df)
    summary.to_csv(out_dir / "summary.csv", index=False)
    json.dump(dict(n_bits=N_BITS, densities_pct=DENSITIES_PCT, iters_low=ITERS_LOW,
                   iters_high=ITERS_HIGH, low_tier_max_pct=LOW_TIER_MAX_PCT,
                   master_seed=MASTER_SEED, input_seed=in_seed, decoders=DECODERS,
                   calibration=cal, elapsed_s=round(time.time() - t0, 1),
                   note="per-iteration seeds are in iterations.csv (column 'seed')"),
              open(out_dir / "run_config.json", "w"), indent=2)

    # cleanup scratch
    for p in work.glob("*"): p.unlink()
    work.rmdir()
    print(f"\nDone in {time.time() - t0:.0f}s.\n  {iters_csv}\n  {out_dir / 'summary.csv'}\n  {out_dir / 'run_config.json'}")
    z = summary[summary.density_pct == 0]
    if len(z) and (z.total_errors > 0).any():
        print("WARNING: errors at 0% density - decoder/testbench problem!")


if __name__ == "__main__":
    main()
