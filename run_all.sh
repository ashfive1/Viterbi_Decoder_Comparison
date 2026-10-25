#!/usr/bin/env bash
# Runs the whole flow: check tools -> BER sweep -> plots.
# Usage:  ./run_all.sh            (full sweep)
#         ./run_all.sh --quick    (small smoke test, ~seconds)
# Extra args are passed to sim/run_sweep.py (see --help there).
set -euo pipefail
cd "$(dirname "$0")"

command -v iverilog >/dev/null || { echo "iverilog not found. Install: sudo apt update && sudo apt install -y iverilog"; exit 1; }
command -v vvp      >/dev/null || { echo "vvp not found (comes with iverilog)."; exit 1; }
command -v python3  >/dev/null || { echo "python3 not found. Install: sudo apt install -y python3 python3-venv"; exit 1; }

PY=python3
if ! python3 -c "import numpy, pandas, matplotlib" 2>/dev/null; then
    echo "Python packages missing -> creating local venv (.venv) ..."
    python3 -m venv .venv || { echo "venv failed. Install: sudo apt install -y python3-venv"; exit 1; }
    .venv/bin/pip install -q -r requirements.txt
    PY=.venv/bin/python
fi

$PY sim/run_sweep.py "$@"
$PY sim/plot_results.py
echo
echo "All done. Results: results/   Plots: results/plots/"
