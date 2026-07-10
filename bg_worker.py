
import random
import traceback
import numpy as np
import torch
import torch.nn as nn

_W = np.array([1., 2., 3., -1., -2., -3.], dtype=np.float32)

# All 21 distinct dice outcomes with their weights (non-doubles appear twice in 36).
_ALL_21_DICE = [(d1, d2) for d1 in range(1, 7) for d2 in range(d1, 7)]
_DICE_WEIGHTS = np.array([1 if d1 == d2 else 2 for d1, d2 in _ALL_21_DICE], dtype=np.float32)


def _encode_boards_batch(boards, player):
    """Vectorized batch encoding of multiple board positions.

    Equivalent to [encode_board(b, player, 1, None) for b in boards] but uses
    numpy array ops instead of Python loops — typically 20-50x faster for the
    large batches produced by 2-ply search.

    boards : list of 26-int board lists
    player : 'WHITE' or 'BLACK'
    returns: (N, 200) float32 numpy array
    """
    N = len(boards)
    arr = np.array(boards, dtype=np.int32)   # (N, 26)
    if player == "BLACK":
        flipped = np.empty_like(arr)
        flipped[:, 0]    = arr[:, 25]         # my bar  = BLACK bar
        flipped[:, 25]   = arr[:, 0]          # opp bar = WHITE bar
        flipped[:, 1:25] = -arr[:, 24:0:-1]    # mirror & negate points: new[i] = -old[25-i]
        arr = flipped
    pts   = arr[:, 1:25]                      # (N, 24)
    mine  = np.maximum(pts,  0)
    theirs = np.maximum(-pts, 0)
    out   = np.zeros((N, 200), dtype=np.float32)
    enc   = np.zeros((N, 24, 8), dtype=np.float32)
    enc[:, :, 0] = mine   >= 1
    enc[:, :, 1] = mine   >= 2
    enc[:, :, 2] = mine   >= 3
    enc[:, :, 3] = np.maximum(mine   - 3, 0) / 2.0
    enc[:, :, 4] = theirs >= 1
    enc[:, :, 5] = theirs >= 2
    enc[:, :, 6] = theirs >= 3
    enc[:, :, 7] = np.maximum(theirs - 3, 0) / 2.0
    out[:, :192] = enc.reshape(N, 192)
    mine_on = mine.sum(axis=1)
    opp_on  = theirs.sum(axis=1)
    out[:, 192] = arr[:, 0]  / 2.0
    out[:, 193] = arr[:, 25] / 2.0
    out[:, 194] = (15 - mine_on - arr[:, 0])  / 15.0
    out[:, 195] = (15 - opp_on  - arr[:, 25]) / 15.0
    out[:, 196] = 1.0 if player == "WHITE" else 0.0
    out[:, 197] = 1.0 / 64.0   # cube = 1
    # out[:, 198] = 0.0         # cube_owner != player (None case)
    out[:, 199] = 1.0           # cube_owner is None
    return out


def initial_board():
    return [0, -2, 0, 0, 0, 0, 5, 0, 3, 0, 0, 0, -5, 5, 0, 0, 0, -3, 0, -5, 0, 0, 0, 0, 2, 0]


def roll_dice():
    d1, d2 = random.randint(1, 6), random.randint(1, 6)
    return [d1, d2, d1, d2] if d1 == d2 else [d1, d2]


def flip_board(board):
    new_board = [0] * 26
    new_board[0] = board[25]
    new_board[25] = board[0]
    for i in range(1, 25):
        new_board[i] = -board[25 - i]
    return new_board


def encode_board(board, player, cube=1, cube_owner=None):
    inputs = []
    if player == "BLACK":
        board = flip_board(board)
    mine_on_board = 0
    opp_on_board  = 0
    for i in range(1, 25):
        n    = board[i]
        mine = max(n, 0)
        inputs.append(1.0 if mine >= 1 else 0.0)
        inputs.append(1.0 if mine >= 2 else 0.0)
        inputs.append(1.0 if mine >= 3 else 0.0)
        inputs.append(max(mine - 3, 0) / 2.0)
        mine_on_board += mine
        theirs = max(-n, 0)
        inputs.append(1.0 if theirs >= 1 else 0.0)
        inputs.append(1.0 if theirs >= 2 else 0.0)
        inputs.append(1.0 if theirs >= 3 else 0.0)
        inputs.append(max(theirs - 3, 0) / 2.0)
        opp_on_board += theirs
    my_off  = 15 - mine_on_board - board[0]
    opp_off = 15 - opp_on_board  - board[25]
    inputs.append(board[0]  / 2.0)
    inputs.append(board[25] / 2.0)
    inputs.append(my_off    / 15.0)
    inputs.append(opp_off   / 15.0)
    inputs.append(1.0 if player == "WHITE" else 0.0)
    inputs.append(cube / 64.0)
    inputs.append(1.0 if cube_owner == player else 0.0)
    inputs.append(1.0 if cube_owner is None   else 0.0)
    return inputs  # 200 floats


def game_outcome(board):
    white_on  = sum(board[i] for i in range(1, 25) if board[i] > 0)
    black_on  = sum(-board[i] for i in range(1, 25) if board[i] < 0)
    white_off = 15 - white_on - board[0]
    black_off = 15 - black_on - board[25]
    if white_off == 15:
        winner = "WHITE"
        loser_off, loser_bar = black_off, board[25]
        loser_in_winner_home = any(board[i] < 0 for i in range(1, 7))
    elif black_off == 15:
        winner = "BLACK"
        loser_off, loser_bar = white_off, board[0]
        loser_in_winner_home = any(board[i] > 0 for i in range(19, 25))
    else:
        return None, None
    if loser_off == 0 and (loser_bar > 0 or loser_in_winner_home):
        return winner, "backgammon"
    if loser_off == 0:
        return winner, "gammon"
    return winner, "win"


_TERMINAL_EQ = {"win": 1.0, "gammon": 2.0, "backgammon": 3.0}


def _terminal_equity(board, pov_player):
    """Exact cubeless equity of a FINISHED board from pov_player's view, else None.

    Fast path: if both colours are still on the board, return None immediately
    without calling game_outcome (handles ~99% of in-game positions in O(k)
    where k is the first point index that has the second colour).
    """
    has_white = board[0] > 0   # white bar counts
    has_black = board[25] > 0  # black bar counts
    for i in range(1, 25):
        if board[i] > 0:
            has_white = True
        elif board[i] < 0:
            has_black = True
        if has_white and has_black:
            return None
    winner, kind = game_outcome(board)
    if winner is None:
        return None
    eq = _TERMINAL_EQ[kind]
    return eq if winner == pov_player else -eq


def outcome_target(winner, outcome_type, current_player):
    t = np.zeros(6, dtype=np.float32)
    if winner == current_player:
        t[{"win": 0, "gammon": 1, "backgammon": 2}[outcome_type]] = 1.0
    else:
        t[{"win": 3, "gammon": 4, "backgammon": 5}[outcome_type]] = 1.0
    return t


def generate_legal_moves(board, dice, player):
    results = []
    _gen(board, list(dice), player, [], results)
    if not results:
        return []
    max_used = max(len(m) for m, _ in results)
    if max_used == 0:
        return []
    candidates = [(m, s) for m, s in results if len(m) == max_used]
    if max_used == 1 and len(dice) == 2 and dice[0] != dice[1]:
        higher = max(dice)
        with_higher = [(m, s) for m, s in candidates if m[0][2] == higher]
        if with_higher:
            candidates = with_higher
    seen, unique = set(), []
    for m, s in candidates:
        key = tuple(s)
        if key not in seen:
            seen.add(key)
            unique.append(m)
    return unique


def _gen(board, remaining, player, current, results):
    singles = _singles(board, remaining, player)
    if not singles:
        results.append((current, board)); return
    tried = set()
    for die in remaining:
        if die in tried: continue
        tried.add(die)
        for m in [s for s in singles if s[2] == die]:
            nxt = list(remaining); nxt.remove(die)
            _gen(_apply_step(board, m, player), nxt, player, current + [m], results)


def _singles(board, dice, player):
    moves = []
    for die in set(dice):
        if player == "WHITE":
            if board[0] > 0:
                to = 25 - die
                if board[to] > -2: moves.append((0, to, die))
            else:
                for pt in range(1, 25):
                    if board[pt] <= 0: continue
                    dest = pt - die
                    if 1 <= dest <= 24:
                        if board[dest] > -2: moves.append((pt, dest, die))
                    elif _can_bear_off_white(board) and _bear_off_ok_white(pt, dest, board):
                        moves.append((pt, -1, die))
        else:
            if board[25] > 0:
                to = die
                if board[to] < 2: moves.append((25, to, die))
            else:
                for pt in range(1, 25):
                    if board[pt] >= 0: continue
                    dest = pt + die
                    if 1 <= dest <= 24:
                        if board[dest] < 2: moves.append((pt, dest, die))
                    elif _can_bear_off_black(board) and _bear_off_ok_black(pt, dest, board):
                        moves.append((pt, 26, die))
    return moves


def _can_bear_off_white(board):
    return board[0] == 0 and all(board[i] <= 0 for i in range(7, 25))

def _can_bear_off_black(board):
    return board[25] == 0 and all(board[i] >= 0 for i in range(1, 19))

def _bear_off_ok_white(point, dest, board):
    if dest == 0: return True
    return all(board[p] <= 0 for p in range(point + 1, 7))

def _bear_off_ok_black(point, dest, board):
    if dest == 25: return True
    return all(board[p] >= 0 for p in range(19, point))

def _apply_step(board, step, player):
    board = list(board)
    frm, to, _ = step
    if player == "WHITE":
        if frm == 0: board[0] -= 1
        else:        board[frm] -= 1
        if to != -1:
            if board[to] == -1: board[to] = 0; board[25] += 1
            board[to] += 1
    else:
        if frm == 25: board[25] -= 1
        else:         board[frm] += 1
        if to != 26:
            if board[to] == 1: board[to] = 0; board[0] += 1
            board[to] -= 1
    return board

def apply_move(board, move, player):
    for step in move:
        board = _apply_step(board, step, player)
    return board


class _WorkerNet(nn.Module):
    def __init__(self, hidden_size):
        super().__init__()
        # Attribute named 'net' so state_dict keys match TDGammon exactly.
        self.net = nn.Sequential(
            nn.Linear(200, hidden_size),
            nn.Sigmoid(),
            nn.Linear(hidden_size, 6),
            nn.Sigmoid()
        )
    def forward(self, x):
        return self.net(x)


def _move_bears_off(move, mover):
    """True iff any step in `move` sends a checker off the board."""
    off = -1 if mover == "WHITE" else 26
    return any(step[1] == off for step in move)


def _choose_1ply_cpu(board, dice, player, net):
    """Pick the move that minimises the opponent's equity (cubeless).
    Encodes each after-move position from the opponent's perspective — the same
    invariant as training: net is only ever queried on the side-about-to-roll."""
    legal_moves = generate_legal_moves(board, dice, player)
    if not legal_moves:
        return None
    opp = "BLACK" if player == "WHITE" else "WHITE"
    after_moves = [apply_move(board, m, player) for m in legal_moves]
    enc = _encode_boards_batch(after_moves, opp)
    with torch.no_grad():
        opp_eq = (net(torch.from_numpy(enc)).numpy() * _W).sum(axis=1)
    # Exact terminal override — only possible when the move bore off a checker.
    for i, b in enumerate(after_moves):
        if _move_bears_off(legal_moves[i], player):
            t = _terminal_equity(b, opp)
            if t is not None:
                opp_eq[i] = t
    return legal_moves[int(opp_eq.argmin())]


def _choose_2ply_cpu(board, dice, player, net, top_k=2, skip_gate=0.10):
    """2-ply expectiminimax move selection for use during self-play training.

    1-ply pre-scores all legal moves, keeps the top_k candidates, then averages the
    opponent's best response over all 21 dice outcomes. All positions across ALL
    top_k candidates are encoded in one numpy call and evaluated in ONE forward pass,
    minimising Python/PyTorch launch overhead.

    skip_gate: if the 1-ply gap between best and second-best exceeds this threshold,
    the result is already decisive and 2-ply expansion is skipped. Pass None to
    always expand (used by regression tests).

    The eval functions in train_1m.py still use _choose_1ply_cpu — only self-play
    move generation upgrades to 2-ply.
    """
    legal_moves = generate_legal_moves(board, dice, player)
    if not legal_moves:
        return None
    if len(legal_moves) == 1:
        return legal_moves[0]

    opp = "BLACK" if player == "WHITE" else "WHITE"

    # 1-ply pre-score: vectorised batch encode + single forward pass.
    after_my_moves = [apply_move(board, m, player) for m in legal_moves]
    enc1 = _encode_boards_batch(after_my_moves, opp)
    with torch.no_grad():
        eq1 = (net(torch.from_numpy(enc1)).numpy() * _W).sum(axis=1)
    # Exact terminal override (opp POV) — only possible when the move bore off.
    for i, b in enumerate(after_my_moves):
        if _move_bears_off(legal_moves[i], player):
            t = _terminal_equity(b, opp)
            if t is not None:
                eq1[i] = t

    k = min(top_k, len(legal_moves))
    top_idx = np.argsort(eq1, kind="stable")[:k]

    # Move filter: if the best 1-ply candidate leads the runner-up decisively,
    # 2-ply expansion is redundant — play it directly.
    if skip_gate is not None and k >= 2 and eq1[top_idx[1]] - eq1[top_idx[0]] > skip_gate:
        return legal_moves[top_idx[0]]

    # --- Build ALL leaf boards for ALL candidates in one pass, then ONE forward pass. ---
    # cand_meta[i] = ("terminal", exact_eq) | ("normal", cand_start, dice_groups)
    # dice_groups  = [(weight, offset_within_cand, n_positions), ...]
    all_boards = []
    cand_meta = []
    leaf_overrides = []   # (global_index, exact_mover_eq) applied after forward pass

    for idx in top_idx:
        after_my = after_my_moves[idx]
        # If our move already ended the game, record exact equity and skip the opp loop.
        if _move_bears_off(legal_moves[idx], player):
            t = _terminal_equity(after_my, player)
            if t is not None:
                cand_meta.append(("terminal", t))
                continue

        cand_start = len(all_boards)
        dice_groups = []
        for (d1, d2), weight in zip(_ALL_21_DICE, _DICE_WEIGHTS):
            opp_dice = [d1, d2, d1, d2] if d1 == d2 else [d1, d2]
            opp_moves = generate_legal_moves(after_my, opp_dice, opp)
            local_start = len(all_boards) - cand_start
            if not opp_moves:
                # Dance: board unchanged; after_my is not terminal (checked above).
                all_boards.append(after_my)
                dice_groups.append((weight, local_start, 1))
            else:
                for om in opp_moves:
                    leaf = apply_move(after_my, om, opp)
                    g = len(all_boards)
                    if _move_bears_off(om, opp):
                        tl = _terminal_equity(leaf, player)
                        if tl is not None:
                            leaf_overrides.append((g, tl))
                    all_boards.append(leaf)
                dice_groups.append((weight, local_start, len(opp_moves)))
        cand_meta.append(("normal", cand_start, dice_groups))

    # One vectorised encode + one forward pass for everything.
    if all_boards:
        enc2 = _encode_boards_batch(all_boards, player)
        with torch.no_grad():
            all_eqs = (net(torch.from_numpy(enc2)).numpy() * _W).sum(axis=1)
        for g, exact in leaf_overrides:
            all_eqs[g] = exact
    else:
        all_eqs = np.empty(0, dtype=np.float32)

    # Pick best candidate — MAXIMISE the mover's expected equity.
    # all_eqs is in the MOVER's frame (leaves encoded with `player`, the side about
    # to roll after the opponent replies). Inner .min() = opp's best reply (hurts
    # mover most); outer selection must max, not min.
    best_eq = float("-inf")
    best_move = legal_moves[top_idx[0]]
    for i, idx in enumerate(top_idx):
        meta = cand_meta[i]
        if meta[0] == "terminal":
            expected_eq = meta[1]
        else:
            _, cand_start, dice_groups = meta
            expected_eq = sum(
                weight * all_eqs[cand_start + start:cand_start + start + n].min()
                for weight, start, n in dice_groups
            ) / 36.0
        if expected_eq > best_eq:
            best_eq = expected_eq
            best_move = legal_moves[idx]

    return best_move


def _play_games(net, n_batch):
    """Self-play n_batch games. Returns a list of (states, terminal_target):
      states          : float32 [T, 200] — pre-roll encodings in turn order,
                        strictly alternating perspective (side about to roll).
      terminal_target : float32 [6] — one-hot outcome from states[-1]'s perspective.
    Games hitting the 10k-turn safety cap are dropped."""
    games = []
    with torch.no_grad():
        for _ in range(n_batch):
            board, player = initial_board(), random.choice(["WHITE", "BLACK"])
            states, terminal = [], None
            for _ in range(10_000):
                states.append(encode_board(board, player, 1, None))
                dice = roll_dice()
                mv = _choose_2ply_cpu(board, dice, player, net)
                if mv is not None:
                    board = apply_move(board, mv, player)
                winner, outcome = game_outcome(board)
                if winner is not None:
                    terminal = outcome_target(winner, outcome, player)
                    break
                player = "BLACK" if player == "WHITE" else "WHITE"
            if terminal is not None:
                games.append((np.asarray(states, dtype=np.float32), terminal))
    return games


def worker_fn(worker_id, task_queue, result_queue, hidden_size):
    torch.set_num_threads(1)          # one core per worker; no oversubscription
    try:
        torch.set_num_interop_threads(1)
    except RuntimeError:
        pass                          # already initialised — intra-op pin still holds
    net = _WorkerNet(hidden_size)
    net.eval()
    try:
        while True:
            msg = task_queue.get()
            if msg is None:
                break
            n_batch, state_dict_np = msg
            net.load_state_dict(
                {k: torch.tensor(v, dtype=torch.float32) for k, v in state_dict_np.items()}
            )
            experience = _play_games(net, n_batch)
            result_queue.put((worker_id, experience))
    except Exception:
        result_queue.put((worker_id, RuntimeError(traceback.format_exc())))
