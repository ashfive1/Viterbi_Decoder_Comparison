#!/usr/bin/env python3
"""Reads results/summary.csv (+ iterations.csv if present) and writes PNG plots to results/plots/."""
import argparse
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
STYLE = {"K3": dict(color="tab:blue", marker="o"), "K7": dict(color="tab:red", marker="s")}


def load(res):
    s = pd.read_csv(res / "summary.csv")
    it = pd.read_csv(res / "iterations.csv") if (res / "iterations.csv").exists() else None
    return s, it


def plot_ber(s, it, path, xmax=None, title_suffix=""):
    fig, ax = plt.subplots(figsize=(8, 5.5))
    s = s[s.density_pct > 0]
    if xmax: s = s[s.density_pct <= xmax]
    floor = np.inf
    for dec, g in s.groupby("decoder"):
        g = g.sort_values("density_pct"); st = STYLE[dec]
        if it is not None:                                   # faint per-iteration scatter
            gi = it[(it.decoder == dec) & (it.density_pct.isin(g.density_pct)) & (it.ber > 0)]
            ax.scatter(gi.density_pct, gi.ber, s=6, alpha=0.15, color=st["color"], linewidths=0)
        nz = g[g.total_errors > 0]
        lo = (nz.mean_ber - nz.ci95_low).fillna(0).clip(lower=0)
        hi = (nz.ci95_high - nz.mean_ber).fillna(0).clip(lower=0)
        ax.errorbar(nz.density_pct, nz.mean_ber, yerr=[lo, hi], label=f"{dec} decoder",
                    capsize=3, lw=1.5, **st)
        z = g[g.total_errors == 0]                           # zero errors -> upper bound, hollow
        ax.scatter(z.density_pct, z.ber_upper95, marker=st["marker"], facecolors="none",
                   edgecolors=st["color"], s=50, label=f"{dec}: 0 errors (95% upper bound)" if len(z) else None)
        floor = min(floor, g.mean_ber[g.mean_ber > 0].min() if (g.mean_ber > 0).any() else floor,
                    z.ber_upper95.min() if len(z) else floor)
    unc = s.drop_duplicates("density_pct").sort_values("density_pct")
    ax.plot(unc.density_pct, unc.uncoded_ber, "k--", lw=1, label="Uncoded (BER = channel error rate)")
    ax.set_yscale("log"); ax.set_xlabel("Error density (% of coded bits flipped)")
    ax.set_ylabel("Decoded BER (uncorrected bits / input bits)")
    ax.set_title("BER vs error density" + title_suffix); ax.grid(True, which="both", alpha=0.3)
    if np.isfinite(floor): ax.set_ylim(bottom=floor / 3)
    ax.legend(fontsize=8); fig.tight_layout(); fig.savefig(path, dpi=150); plt.close(fig)


def plot_simple(s, col, ylabel, title, path, logy=False, hollow_col=None, hline=None, nz_only=False):
    fig, ax = plt.subplots(figsize=(8, 5))
    s = s[s.density_pct > 0]
    for dec, g in s.groupby("decoder"):
        g = g.sort_values("density_pct"); st = STYLE[dec]
        gg = g[g.total_errors > 0] if nz_only else g
        solid = g[g.total_errors > 0]
        ax.plot(solid.density_pct, solid[col], label=dec, lw=1.5, **st) if not nz_only else \
            ax.plot(gg.density_pct, gg[col], label=dec, lw=1.5, **st)
        if hollow_col:
            z = g[g.total_errors == 0]
            ax.scatter(z.density_pct, z[hollow_col], marker=st["marker"], facecolors="none",
                       edgecolors=st["color"], s=50, label=f"{dec} (lower bound, 0 errors)" if len(z) else None)
    if hline is not None: ax.axhline(hline, color="k", ls="--", lw=1)
    if logy: ax.set_yscale("log")
    ax.set_xlabel("Error density (% of coded bits flipped)"); ax.set_ylabel(ylabel)
    ax.set_title(title); ax.grid(True, which="both", alpha=0.3); ax.legend(fontsize=8)
    fig.tight_layout(); fig.savefig(path, dpi=150); plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", default=str(ROOT / "results"))
    a = ap.parse_args()
    res = Path(a.results); out = res / "plots"; out.mkdir(parents=True, exist_ok=True)
    s, it = load(res)
    plot_ber(s, it, out / "1_ber_vs_density.png")
    plot_ber(s, it, out / "1b_ber_vs_density_low_end_zoom.png", xmax=15, title_suffix=" (0-15% zoom)")
    plot_simple(s, "frame_error_rate", "Fraction of iterations with >=1 residual error",
                "Frame error rate vs error density", out / "2_frame_error_rate.png")
    plot_simple(s, "mean_burst_len", "Mean residual error burst length (bits)",
                "Residual error burst length vs error density", out / "3_burst_length.png", nz_only=True)
    plot_simple(s, "ber_gain", "Uncoded BER / decoded BER (>1 = decoder helps)",
                "BER gain vs error density", out / "4_ber_gain.png", logy=True,
                hollow_col="ber_gain_lower_bound", hline=1.0)
    print("Plots written to", out)
    for f in sorted(out.glob("*.png")): print("  ", f.name)


if __name__ == "__main__":
    main()
