"""
Regression tests for the 2-ply expectiminimax fix in bg_worker.py.

Run:   python test_two_ply.py
Exit:  0 on success, 1 on any failure.
"""

import random
import sys

import numpy as np
import torch
import torch.nn as nn

# Fixed seeds so the test is deterministic and reproducible.
random.seed(0)
np.random.seed(0)
torch.manual_seed(0)

import bg_worker as bw

# ── Tiny net (random weights, same shape as the real model) ─────────────────
class _TinyNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(200, 40)
        self.fc2 = nn.Linear(40, 6)

    def forward(self, x):
        return torch.sigmoid(self.fc2(torch.sigmoid(self.fc1(x))))


_net = _TinyNet()
_net.eval()

_W = np.array([1., 2., 3., -1., -2., -3.], dtype=np.float32)
_ALL_21 = [(d1, d2) for d1 in range(1, 7) for d2 in range(d1, 7)]
_WEIGHTS = [1 if d1 == d2 else 2 for d1, d2 in _ALL_21]


# ── Scalar leaf-equity helper ────────────────────────────────────────────────

def _leaf_eq(board, pov_player):
    """Equity from pov_player's frame — exact if terminal, net eval otherwise."""
    t = bw._terminal_equity(board, pov_player)
    if t is not None:
        return t
    enc = bw.encode_board(board, pov_player, 1, None)
    x = torch.tensor([enc], dtype=torch.float32)
    with torch.no_grad():
        v = _net(x).numpy()[0]
    return float((v * _W).sum())


# ── 3a — Reference 2-ply using plain Python loops ───────────────────────────

def choose_2ply_reference(board, dice, player, top_k=2):
    """Correct 2-ply minimax expressed directly — the spec's ground truth.

    Returns (best_move, best_expected_eq).
    """
    legal = bw.generate_legal_moves(board, dice, player)
    if not legal:
        return None, None
    opp = "BLACK" if player == "WHITE" else "WHITE"

    # 1-ply pre-score from opp's POV (exact if terminal).
    opp_eqs = []
    after_my_list = []
    for m in legal:
        after_my = bw.apply_move(board, m, player)
        after_my_list.append(after_my)
        t = bw._terminal_equity(after_my, opp)
        opp_eqs.append(t if t is not None else _leaf_eq(after_my, opp))

    k = min(top_k, len(legal))
    top_idx = sorted(range(len(legal)), key=lambda i: opp_eqs[i])[:k]

    best_exp = float("-inf")
    best_move = legal[top_idx[0]]

    for idx in top_idx:
        after_my = after_my_list[idx]

        # Candidate already ends the game → exact equity for the mover.
        t_my = bw._terminal_equity(after_my, player)
        if t_my is not None:
            exp = t_my
        else:
            total = 0.0
            for (d1, d2), w in zip(_ALL_21, _WEIGHTS):
                opp_dice = [d1, d2, d1, d2] if d1 == d2 else [d1, d2]
                opp_moves = bw.generate_legal_moves(after_my, opp_dice, opp)
                if not opp_moves:
                    # Dance: board unchanged.
                    total += w * _leaf_eq(after_my, player)
                else:
                    # Opp picks the reply that hurts the mover most → min.
                    best_opp = min(
                        _leaf_eq(bw.apply_move(after_my, om, opp), player)
                        for om in opp_moves
                    )
                    total += w * best_opp
            exp = total / 36.0

        if exp > best_exp:
            best_exp = exp
            best_move = legal[idx]

    return best_move, best_exp


def _ref_expected_eq(board, move, player):
    """Expected equity for a specific move via the reference machinery."""
    opp = "BLACK" if player == "WHITE" else "WHITE"
    after_my = bw.apply_move(board, move, player)
    t_my = bw._terminal_equity(after_my, player)
    if t_my is not None:
        return t_my
    total = 0.0
    for (d1, d2), w in zip(_ALL_21, _WEIGHTS):
        opp_dice = [d1, d2, d1, d2] if d1 == d2 else [d1, d2]
        opp_moves = bw.generate_legal_moves(after_my, opp_dice, opp)
        if not opp_moves:
            total += w * _leaf_eq(after_my, player)
        else:
            best_opp = min(
                _leaf_eq(bw.apply_move(after_my, om, opp), player)
                for om in opp_moves
            )
            total += w * best_opp
    return total / 36.0


# ── Position generator ───────────────────────────────────────────────────────

def _random_midgame_positions(n=25):
    """Generate n mid-game positions by playing 4–30 random plies."""
    positions = []
    attempts = 0
    rng_players = ["WHITE", "BLACK"]
    while len(positions) < n and attempts < 2000:
        attempts += 1
        board = bw.initial_board()
        player = random.choice(rng_players)
        plies = random.randint(4, 30)
        ok = True
        for _ in range(plies):
            dice = [random.randint(1, 6), random.randint(1, 6)]
            if dice[0] == dice[1]:
                dice = dice * 2
            moves = bw.generate_legal_moves(board, dice, player)
            if not moves:
                player = "BLACK" if player == "WHITE" else "WHITE"
                continue
            board = bw.apply_move(board, random.choice(moves), player)
            if bw.game_outcome(board)[0] is not None:
                ok = False
                break
            player = "BLACK" if player == "WHITE" else "WHITE"
        if not ok:
            continue
        # Test dice for the search (non-doubles for variety).
        test_dice = [random.randint(1, 5), random.randint(1, 5)]
        while test_dice[0] == test_dice[1]:
            test_dice[1] = random.randint(1, 6)
        moves = bw.generate_legal_moves(board, test_dice, player)
        if len(moves) < 2:
            continue
        positions.append((board, test_dice, player))
    return positions


# ── 3b — Agreement test ──────────────────────────────────────────────────────

def test_agreement(positions):
    failures = 0
    for pos_idx, (board, dice, player) in enumerate(positions):
        ref_move, ref_best_exp = choose_2ply_reference(board, dice, player, top_k=2)
        # skip_gate=None: always expand — exercises the full 2-ply path.
        fast_move = bw._choose_2ply_cpu(board, dice, player, _net, top_k=2, skip_gate=None)

        if fast_move is None or ref_move is None:
            continue

        # Compute the reference expected equity of the fast path's chosen move.
        fast_exp = _ref_expected_eq(board, fast_move, player)

        # fast_exp must be within 1e-4 of the true optimum (ref_best_exp).
        if fast_exp < ref_best_exp - 1e-4:
            legal = bw.generate_legal_moves(board, dice, player)
            all_exps = [_ref_expected_eq(board, m, player) for m in legal]
            best_all = max(all_exps)
            print(
                f"  FAIL pos#{pos_idx}: fast_exp={fast_exp:.6f}  "
                f"ref_best={ref_best_exp:.6f}  overall_best={best_all:.6f}  "
                f"gap={ref_best_exp - fast_exp:.2e}  player={player}"
            )
            failures += 1

        # Gated path: default skip_gate=0.10 may legitimately pick the 1-ply move,
        # but its 2-ply expectation must be within 0.05 of the true optimum.
        gated_move = bw._choose_2ply_cpu(board, dice, player, _net, top_k=2)
        if gated_move is not None:
            gated_exp = _ref_expected_eq(board, gated_move, player)
            if gated_exp < ref_best_exp - 0.05:
                print(
                    f"  FAIL gated pos#{pos_idx}: gated_exp={gated_exp:.6f}  "
                    f"ref_best={ref_best_exp:.6f}  gap={ref_best_exp - gated_exp:.2e}  "
                    f"player={player}"
                )
                failures += 1

    return failures


# ── 3c — Terminal equity unit tests ─────────────────────────────────────────

def test_terminal_equity():
    failures = 0

    def check(label, board, pov, expected):
        nonlocal failures
        got = bw._terminal_equity(board, pov)
        if got != expected:
            print(f"  FAIL {label}: got {got}, expected {expected}")
            failures += 1

    # White normal win: all white borne off, 10 black on + 5 off → loser_off>0 → win.
    b_win = [0] * 26
    b_win[22] = -3
    b_win[21] = -3
    b_win[20] = -4   # black_on=10, black_off=5 → WHITE wins, not gammon
    check("white_win   WHITE POV",  b_win, "WHITE",  1.0)
    check("white_win   BLACK POV",  b_win, "BLACK", -1.0)

    # White gammon: all white off, all 15 black still on, none in white home (1-6).
    b_gam2 = [0] * 26
    b_gam2[20] = -5
    b_gam2[19] = -5
    b_gam2[18] = -5   # 15 black, 0 off, pts 18-20 are NOT in white home (1-6) → gammon
    check("white_gammon WHITE POV", b_gam2, "WHITE",  2.0)
    check("white_gammon BLACK POV", b_gam2, "BLACK", -2.0)

    # White backgammon: all white off, black has checker on bar.
    b_bg = [0] * 26
    b_bg[20] = -5
    b_bg[19] = -5
    b_bg[18] = -4
    b_bg[25] = 1    # black bar (index 25 in Python convention) → backgammon
    check("white_backgammon WHITE POV", b_bg, "WHITE",  3.0)
    check("white_backgammon BLACK POV", b_bg, "BLACK", -3.0)

    # Black normal win: all black borne off, 10 white on + 5 off → loser_off>0 → win.
    b_bwin = [0] * 26
    b_bwin[3] = 3
    b_bwin[4] = 3
    b_bwin[5] = 4   # white_on=10, white_off=5 → BLACK wins, not gammon
    check("black_win   BLACK POV",  b_bwin, "BLACK",  1.0)
    check("black_win   WHITE POV",  b_bwin, "WHITE", -1.0)

    # Non-terminal: starting position.
    init = bw.initial_board()
    got = bw._terminal_equity(init, "WHITE")
    if got is not None:
        print(f"  FAIL non_terminal: got {got}, expected None")
        failures += 1

    return failures


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    total_failures = 0

    print("3c  Terminal equity unit tests...")
    f = test_terminal_equity()
    total_failures += f
    print(f"    {'OK' if f == 0 else f'FAILED ({f})'}")

    print("3b  Generating ~25 mid-game positions...")
    positions = _random_midgame_positions(25)
    print(f"    Got {len(positions)} positions.")

    print("3b  Agreement test (fast vs reference 2-ply)...")
    f = test_agreement(positions)
    total_failures += f
    print(f"    {'OK' if f == 0 else f'FAILED ({f}/{len(positions)})'}")

    if total_failures:
        print(f"\n{total_failures} test(s) FAILED.")
        sys.exit(1)
    else:
        print("\nALL TESTS PASSED")
        sys.exit(0)


if __name__ == "__main__":
    main()
