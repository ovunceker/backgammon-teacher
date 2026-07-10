"""
Standalone TD-Gammon trainer with TD(λ) and batched semi-gradient updates.

Workers self-play and ship raw trajectories (states + terminal target). The master
computes forward-view TD(λ) targets fresh on the current weights, does one batched
SGD step per game, and applies gradient clipping + linear lr decay. Architecture
stays 200→160→6 throughout.

Run:
    python -u train_1m.py            # 1,000,000 games, sensible defaults
Monitor:
    tail -f training.log
Resume from the last checkpoint:
    python -u train_1m.py --resume
"""
import argparse
import copy
import json
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

# Perspective swap: opponent's [win, gwin, bgwin, loss, gloss, bgloss] → my view.
# Vectors SWAP (my_vec = opp_vec[_SWAP]); scalar equity just negates.
_SWAP = torch.tensor([3, 4, 5, 0, 1, 2], device=DEVICE)

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


# --------------------------------------------------------------------------- #
# TD(λ) targets — forward view with alternating perspective.
# --------------------------------------------------------------------------- #
def lambda_returns(values, terminal_target, lam):
    """Compute forward-view TD(λ) return targets for a single trajectory.

    values          : [T, 6] detached net outputs, alternating perspectives.
    terminal_target : [6] outcome vector from states[-1]'s perspective.

    Recurrence (perspective alternates each step, so swap at each level):
        G[T-1] = terminal_target
        G[t]   = ((1-λ) * values[t+1] + λ * G[t+1])[SWAP]

    λ=0 → TD(0) (pure bootstrap); λ=1 → Monte-Carlo (pure outcome).
    Tesauro used λ≈0.7, blending both.
    """
    T = values.shape[0]
    G = torch.empty_like(values)
    G[T - 1] = terminal_target
    for t in range(T - 2, -1, -1):
        G[t] = ((1.0 - lam) * values[t + 1] + lam * G[t + 1])[_SWAP]
    return G


def train_on_game(net, states_np, terminal_np, lam, clip):
    """One batched semi-gradient step for a single trajectory.

    Targets are computed fresh on the current weights (no staleness).
    Returns the mean absolute TD residual for telemetry.
    """
    x = torch.from_numpy(states_np)                         # [T, 200]
    v = net(x)                                              # [T, 6], with grad
    G = lambda_returns(v.detach(), torch.from_numpy(terminal_np), lam)
    # Sum over steps (not mean): each position gets its full gradient, matching
    # the per-position update magnitude of classic online TD. A mean here scales
    # the effective lr by 1/T (~1/50) and the net never leaves its random init.
    loss = 0.5 * ((G - v) ** 2).sum(dim=1).sum()
    net.optimizer.zero_grad()
    loss.backward()
    torch.nn.utils.clip_grad_norm_(net.parameters(), clip)
    net.optimizer.step()
    return float((G - v.detach()).abs().mean().item())


# --------------------------------------------------------------------------- #
# Evaluation
# --------------------------------------------------------------------------- #
def win_rate_vs_snapshot(net, snapshot, n_games=500):
    """Current net vs snapshot from eval_every games ago. Alternates colours
    to cancel the model's residual colour bias — measures quality only."""
    net.eval(); snapshot.eval()
    wins = 0
    with torch.no_grad():
        for g in range(n_games):
            net_color = "WHITE" if g % 2 == 0 else "BLACK"
            snap_color = "BLACK" if g % 2 == 0 else "WHITE"
            board, player = bw.initial_board(), "WHITE"
            for _ in range(10_000):
                cur = net if player == net_color else snapshot
                dice = bw.roll_dice()
                mv = bw._choose_1ply_cpu(board, dice, player, cur)
                if mv is not None:
                    board = bw.apply_move(board, mv, player)
                w, _ = bw.game_outcome(board)
                if w is not None:
                    wins += w == net_color
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
                    mv = bw._choose_1ply_cpu(board, dice, player, net)
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
    os.replace(tmp, path)  # atomic on the same filesystem


def save_provenance(path, total, lam, lr, lr_final, clip, hidden_size):
    meta = {
        "total_games": total, "lam": lam, "lr": lr, "lr_final": lr_final,
        "clip": clip, "hidden_size": hidden_size,
        "engine": "td_lambda_batched_v3_sumloss",
        "saved_at": datetime.now().isoformat(timespec="seconds"),
    }
    with open(path + ".json", "w") as f:
        json.dump(meta, f, indent=2)


def log(msg):
    # Single writer: print to stdout only. Shell redirect owns the log file.
    print(msg, flush=True)


# --------------------------------------------------------------------------- #
# Training
# --------------------------------------------------------------------------- #
def train_parallel(n_games, lr, lr_final, lam, clip, hidden_size, n_workers, n_batch,
                   print_every, eval_every, checkpoint_every,
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
    total_pos = 0
    resid_ema = 0.0
    log(f"=== TD-Gammon training: {n_games:,} games | {n_workers} workers x "
        f"{n_batch}/batch | lam={lam} lr={lr}→{lr_final} clip={clip} | "
        f"master=CPU | started {datetime.now():%Y-%m-%d %H:%M} ===")
    log(f"{'Games':>10}  {'Prog':>6}  {'g/s':>7}  {'plies':>6}  {'pos/s':>7}  {'Elapsed':>9}  "
        f"{'ETA':>9}  {'Finish~':>8}  {'resid':>8}  {'vsSnap':>7}  {'vsRand':>7}")
    log("-" * 110)

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

        # λ-return batched update: one backward per game, targets computed fresh.
        net.train()
        for states_np, terminal_np in payload:
            if states_np.ndim != 2 or states_np.shape[1] != 200 or terminal_np.shape != (6,):
                raise RuntimeError(
                    f"Worker payload shape mismatch: got states{states_np.shape} "
                    f"terminal{terminal_np.shape}, expected states[T,200] terminal[6]. "
                    f"bg_worker.py and train_1m.py are out of sync — check _play_games."
                )
            total_pos += states_np.shape[0]
            r = train_on_game(net, states_np, terminal_np, lam, clip)
            resid_ema = 0.999 * resid_ema + 0.001 * r

        task_queues[wid].put((n_batch, get_weights()))

        prev = total
        total += len(payload)   # dropped games (10k cap) don't count

        # Linear lr annealing — updated after each batch.
        cur_lr = lr + (lr_final - lr) * min(total / n_games, 1.0)
        net.optimizer.param_groups[0]["lr"] = cur_lr

        if total - last_ckpt >= checkpoint_every:
            atomic_save(net, ckpt_path)
            save_provenance(ckpt_path, total, lam, lr, lr_final, clip, hidden_size)
            last_ckpt = total

        if total // print_every > prev // print_every:
            elapsed = time.time() - t0
            gps = total / elapsed
            eta = (n_games - total) / gps if gps > 0 else 0
            finish = (datetime.now() + timedelta(seconds=eta)).strftime("%H:%M")
            pct = min(total / n_games * 100, 100.0)
            if total // eval_every > prev // eval_every:
                # vsSnap: compare current net vs snapshot from eval_every games ago.
                # Snapshot is updated AFTER this comparison so vsSnap is always meaningful.
                wr_s = f"{win_rate_vs_snapshot(net, snapshot):6.1%}"
                rr = win_rate_vs_random(net)
                rr_s = f"{rr:6.1%}"
                snapshot = copy.deepcopy(net)   # update AFTER eval
            else:
                wr_s = f"{'—':>6}"
                rr_s = f"{'—':>6}"
            log(f"{total:>10,}  {pct:>5.1f}%  {gps:>7.1f}  "
                f"{total_pos / max(total, 1):>6.1f}  {total_pos / elapsed:>7.0f}  "
                f"{fmt_dur(elapsed):>9}  "
                f"{fmt_dur(eta):>9}  {finish:>8}  {resid_ema:>8.5f}  {wr_s:>7}  {rr_s:>7}")

    atomic_save(net, ckpt_path)
    save_provenance(ckpt_path, total, lam, lr, lr_final, clip, hidden_size)
    for q in task_queues:
        q.put(None)
    for p in workers:
        p.join(timeout=5)
        if p.is_alive():
            p.terminate()

    log("-" * 93)
    log(f"Done. {total:,} games in {fmt_dur(time.time() - t0)}. Saved {ckpt_path}.")
    return net


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n_games",          type=int,   default=1_000_000)
    ap.add_argument("--lr",               type=float, default=0.01)
    ap.add_argument("--lr_final",         type=float, default=0.005)
    # λ=1.0 (pure Monte-Carlo targets) is load-bearing here: with λ<1 the
    # bootstrap term anchors targets to the net's own race-biased values,
    # self-play stops hitting within ~2k games, and the bar inputs never get
    # training data (measured: vsRand decays to <50%; λ=1.0 hits 97% by 4k games).
    ap.add_argument("--lam",              type=float, default=1.0)
    ap.add_argument("--clip",             type=float, default=20.0)
    ap.add_argument("--hidden",           type=int,   default=160)
    ap.add_argument("--workers",          type=int,   default=9)
    ap.add_argument("--batch",            type=int,   default=4)
    ap.add_argument("--print_every",      type=int,   default=5_000)
    ap.add_argument("--eval_every",       type=int,   default=100_000)
    ap.add_argument("--checkpoint_every", type=int,   default=25_000)
    ap.add_argument("--ckpt",             type=str,   default="tdgammon.pt")
    ap.add_argument("--resume",           action="store_true")
    a = ap.parse_args()

    train_parallel(a.n_games, a.lr, a.lr_final, a.lam, a.clip, a.hidden,
                   a.workers, a.batch, a.print_every, a.eval_every,
                   a.checkpoint_every, a.ckpt, a.resume)
