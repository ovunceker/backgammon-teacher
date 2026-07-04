"""
Standalone 1M-game TD-Gammon trainer.

Reuses the validated CPU game logic in bg_worker.py (self-play workers) and runs
the master TD updates on the CPU — benchmarked 3x faster than MPS for this tiny
200->160->6 net, because single-sample updates are dominated by GPU launch
overhead, not matrix math.

Learning math is IDENTICAL to the notebook's train_parallel (single-sample TD
updates replayed on the master net). Adds: live ETA, wall-clock finish estimate,
and crash-safe periodic checkpointing.

Run:
    python -u train_1m.py            # 1,000,000 games, sensible defaults
Monitor:
    tail -f training.log
Resume from the last checkpoint:
    python -u train_1m.py --resume
"""
import argparse
import copy
import os
import queue
import random
import sys
import time
import multiprocessing as mp
from datetime import datetime, timedelta

import torch
import torch.nn as nn

# Master runs on CPU (proven faster than MPS for single-sample updates here).
DEVICE = torch.device("cpu")
torch.set_num_threads(1)  # keep the master thread lean; cores go to workers

# Ensure a fresh bg_worker is importable (workers re-import it under spawn).
if "bg_worker" in sys.modules:
    del sys.modules["bg_worker"]
import bg_worker as bw


# --------------------------------------------------------------------------- #
# Master network — architecture + state_dict keys must match bw._WorkerNet.
# --------------------------------------------------------------------------- #
class TDGammon(nn.Module):
    def __init__(self, hidden_size=160, lr=0.01):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(200, hidden_size), nn.Sigmoid(),
            nn.Linear(hidden_size, 6), nn.Sigmoid(),
        )
        self.to(DEVICE)
        self.optimizer = torch.optim.SGD(self.parameters(), lr=lr)

    def forward(self, x):
        return self.net(x)

    def td_update(self, v, delta):
        if not isinstance(delta, torch.Tensor):
            delta = torch.tensor(delta, dtype=torch.float32, device=DEVICE)
        self.optimizer.zero_grad()
        loss = -(delta.detach() * v).sum()
        loss.backward()
        self.optimizer.step()


# --------------------------------------------------------------------------- #
# Evaluation — current net (WHITE) vs a past snapshot (BLACK), 1-ply, CPU.
# Reuses bw's game logic so it stays identical to the trained dynamics.
# --------------------------------------------------------------------------- #
def win_rate_vs_snapshot(net, snapshot, n_games=500):
    """Current net (WHITE) vs a past snapshot (BLACK), cubeless — both sides just
    alternate rolls and moves until game_outcome returns a winner."""
    net.eval(); snapshot.eval()
    wins = 0
    with torch.no_grad():
        for _ in range(n_games):
            board, player = bw.initial_board(), "WHITE"
            for _ in range(10_000):
                cur = net if player == "WHITE" else snapshot
                dice = bw.roll_dice()
                mv = bw._choose_1ply_cpu(board, dice, player, cur, 1, None)
                if mv is not None:
                    board = bw.apply_move(board, mv, player)
                w, _ = bw.game_outcome(board)
                if w is not None:
                    if w == "WHITE":
                        wins += 1
                    break
                player = "BLACK" if player == "WHITE" else "WHITE"
    net.train()
    return wins / n_games


def win_rate_vs_random(net, n_games=500):
    """Net vs uniform-random legal-move player. Alternates colors to cancel
    the first-move advantage (this engine always starts with WHITE)."""
    net.eval()
    wins = 0
    with torch.no_grad():
        for g in range(n_games):
            net_color = "WHITE" if g % 2 == 0 else "BLACK"
            board, player = bw.initial_board(), "WHITE"
            for _ in range(10_000):
                dice = bw.roll_dice()
                if player == net_color:
                    mv = bw._choose_1ply_cpu(board, dice, player, net, 1, None)
                else:
                    legal = bw.generate_legal_moves(board, dice, player)
                    mv = random.choice(legal) if legal else None
                if mv is not None:
                    board = bw.apply_move(board, mv, player)
                w, _ = bw.game_outcome(board)
                if w is not None:
                    wins += w == net_color
                    break
                player = "BLACK" if player == "WHITE" else "WHITE"
    net.train()
    return wins / n_games


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
def fmt_dur(sec):
    sec = int(max(sec, 0))
    return f"{sec // 3600:d}:{(sec % 3600) // 60:02d}:{sec % 60:02d}"


def atomic_save(net, path):
    tmp = path + ".tmp"
    torch.save(net.state_dict(), tmp)
    os.replace(tmp, path)  # atomic on the same filesystem — never a half-written file


def log(msg):
    # Single writer: print to stdout only. The shell redirect owns the log file,
    # so tracebacks (stderr) and progress land in one clean stream.
    print(msg, flush=True)


# --------------------------------------------------------------------------- #
# Training
# --------------------------------------------------------------------------- #
def train_parallel(n_games, lr, hidden_size, n_workers, n_batch,
                   print_every, eval_every, snapshot_every, checkpoint_every,
                   ckpt_path, resume):
    bw_module = bw

    try:
        mp.set_start_method("spawn", force=True)
    except RuntimeError:
        pass

    net = TDGammon(hidden_size=hidden_size, lr=lr)
    if resume and os.path.exists(ckpt_path):
        net.load_state_dict(torch.load(ckpt_path, map_location="cpu"))
        print(f"Resumed weights from {ckpt_path}")
    snapshot = copy.deepcopy(net)

    def get_weights():
        return {k: v.cpu().numpy() for k, v in net.state_dict().items()}

    result_queue = mp.Queue()
    task_queues = [mp.Queue() for _ in range(n_workers)]

    def spawn_worker(wid):
        p = mp.Process(target=bw_module.worker_fn,
                       args=(wid, task_queues[wid], result_queue, hidden_size),
                       daemon=True)
        p.start()
        return p

    init_w = get_weights()
    workers = [spawn_worker(w) for w in range(n_workers)]
    for q in task_queues:
        q.put((n_batch, init_w))

    t0 = time.time()
    total = 0
    log(f"=== TD-Gammon training: {n_games:,} games | {n_workers} workers x "
        f"{n_batch}/batch | master=CPU | started {datetime.now():%Y-%m-%d %H:%M} ===")
    log(f"{'Games':>10}  {'Prog':>6}  {'g/s':>7}  {'Elapsed':>9}  "
        f"{'ETA':>9}  {'Finish~':>8}  {'vsSnap':>7}  {'vsRand':>7}")
    log("-" * 84)

    last_ckpt = 0
    while total < n_games:
        try:
            wid, payload = result_queue.get(timeout=120)
        except queue.Empty:
            for i, p in enumerate(workers):
                if not p.is_alive():
                    log(f"Worker {i} died — restarting.")
                    workers[i] = spawn_worker(i)
                    task_queues[i].put((n_batch, get_weights()))
            continue

        if isinstance(payload, Exception):
            log(f"Worker {wid} error:\n{payload}")
            workers[wid].terminate()
            workers[wid] = spawn_worker(wid)
            task_queues[wid].put((n_batch, get_weights()))
            continue

        # Replay worker experience through the master net (single-sample TD).
        net.train()
        for enc, delta in payload:
            v = net(torch.tensor(enc, dtype=torch.float32, device=DEVICE))
            net.td_update(v, torch.tensor(delta, dtype=torch.float32, device=DEVICE))

        task_queues[wid].put((n_batch, get_weights()))  # keep the worker busy

        prev = total
        total += n_batch

        if total // snapshot_every > prev // snapshot_every:
            snapshot = copy.deepcopy(net)

        if total - last_ckpt >= checkpoint_every:
            atomic_save(net, ckpt_path)
            last_ckpt = total

        if total // print_every > prev // print_every:
            elapsed = time.time() - t0
            gps = total / elapsed
            eta = (n_games - total) / gps if gps > 0 else 0
            finish = (datetime.now() + timedelta(seconds=eta)).strftime("%H:%M")
            pct = min(total / n_games * 100, 100.0)
            if total // eval_every > prev // eval_every:
                wr_s = f"{win_rate_vs_snapshot(net, snapshot):6.1%}"
                rr_s = f"{win_rate_vs_random(net):6.1%}"
            else:
                wr_s = f"{'—':>6}"
                rr_s = f"{'—':>6}"
            log(f"{total:>10,}  {pct:>5.1f}%  {gps:>7.1f}  {fmt_dur(elapsed):>9}  "
                f"{fmt_dur(eta):>9}  {finish:>8}  {wr_s:>7}  {rr_s:>7}")

    atomic_save(net, ckpt_path)
    for q in task_queues:
        q.put(None)
    for p in workers:
        p.join(timeout=5)
        if p.is_alive():
            p.terminate()

    log("-" * 74)
    log(f"Done. {total:,} games in {fmt_dur(time.time() - t0)}. Saved {ckpt_path}")
    return net


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n_games", type=int, default=1_000_000)
    ap.add_argument("--lr", type=float, default=0.01)
    ap.add_argument("--hidden", type=int, default=160)
    ap.add_argument("--workers", type=int, default=7)
    ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--print_every", type=int, default=5_000)
    ap.add_argument("--eval_every", type=int, default=100_000)
    ap.add_argument("--snapshot_every", type=int, default=100_000)
    ap.add_argument("--checkpoint_every", type=int, default=25_000)
    ap.add_argument("--ckpt", type=str, default="tdgammon.pt")
    ap.add_argument("--resume", action="store_true")
    a = ap.parse_args()

    train_parallel(a.n_games, a.lr, a.hidden, a.workers, a.batch,
                   a.print_every, a.eval_every, a.snapshot_every,
                   a.checkpoint_every, a.ckpt, a.resume)
