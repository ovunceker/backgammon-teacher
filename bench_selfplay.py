"""
Single-process benchmark for bg_worker self-play throughput.

Measures per-worker compute only — the Task 1 oversubscription fix (thread pinning)
shows up in the full multi-worker run, not here.

Usage:
    python bench_selfplay.py              # 20 games, default skip_gate=0.10
    python bench_selfplay.py --games 50  # more games for stable numbers
    python bench_selfplay.py --no-gate   # always do full 2-ply expansion
    python bench_selfplay.py --gate 0.05 # tighter gate
"""

import argparse
import cProfile
import functools
import io
import os
import pstats
import random
import time

import torch

torch.set_num_threads(1)

import bg_worker as bw

# ── Argument parsing ──────────────────────────────────────────────────────────

parser = argparse.ArgumentParser()
parser.add_argument("--games",   type=int,   default=20,   help="Number of games to play")
parser.add_argument("--gate",    type=float, default=0.10, help="skip_gate value (ignored with --no-gate)")
parser.add_argument("--no-gate", action="store_true",      help="Disable skip_gate (always full 2-ply)")
args = parser.parse_args()

N = args.games
gate = None if args.no_gate else args.gate

# ── Fixed seeds ───────────────────────────────────────────────────────────────

random.seed(0)
torch.manual_seed(0)

# ── Load or init net ──────────────────────────────────────────────────────────

CKPT = os.path.join(os.path.dirname(__file__), "tdgammon.pt")
net = bw._WorkerNet(160)
net.eval()
if os.path.exists(CKPT):
    state = torch.load(CKPT, map_location="cpu", weights_only=True)
    net.load_state_dict(state)
    print(f"Loaded checkpoint: {CKPT}")
else:
    print("No checkpoint found — using random weights.")

print(f"Running {N} games  |  skip_gate={gate}  |  torch_threads={torch.get_num_threads()}")
print()

# ── Monkey-patch skip_gate into _choose_2ply_cpu ─────────────────────────────

bw._choose_2ply_cpu = functools.partial(bw._choose_2ply_cpu, skip_gate=gate)

# ── Profile ───────────────────────────────────────────────────────────────────

pr = cProfile.Profile()
t0 = time.perf_counter()
pr.enable()
games = bw._play_games(net, N)
pr.disable()
elapsed = time.perf_counter() - t0

# ── Report ────────────────────────────────────────────────────────────────────

total_pos = sum(s.shape[0] for s, _ in games)
gps = len(games) / elapsed
pps = total_pos / elapsed
avg_plies = total_pos / max(len(games), 1)

print(f"Games played : {len(games)}")
print(f"Wall time    : {elapsed:.2f}s")
print(f"Games/s      : {gps:.2f}")
print(f"Avg plies    : {avg_plies:.1f}")
print(f"Positions/s  : {pps:.0f}")
print()

s = io.StringIO()
ps = pstats.Stats(pr, stream=s).sort_stats("cumulative")
ps.print_stats(15)
print(s.getvalue())
