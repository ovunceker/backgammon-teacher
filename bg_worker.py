
import random
import traceback
import numpy as np
import torch
import torch.nn as nn

DOUBLE_THRESHOLD = 0.5
DROP_THRESHOLD   = 0.75
_W = np.array([1., 2., 3., -1., -2., -3.], dtype=np.float32)


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
        new_board[i] = -board[26 - i]
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


def _choose_1ply_cpu(board, dice, player, net, cube, cube_owner):
    legal_moves = generate_legal_moves(board, dice, player)
    if not legal_moves:
        return None
    encodings = [encode_board(apply_move(board, m, player), player, cube, cube_owner)
                 for m in legal_moves]
    batch = torch.tensor(encodings, dtype=torch.float32)
    with torch.no_grad():
        eqs = (net(batch).numpy() * _W).sum(axis=1)
    return legal_moves[int(eqs.argmax())]


def _play_games(net, n_batch):
    experience = []
    win_target = np.array([1., 0., 0., 0., 0., 0.], dtype=np.float32)
    with torch.no_grad():
        for _ in range(n_batch):
            board      = initial_board()
            player     = "WHITE"
            cube_value = 1
            cube_owner = None
            for _ in range(10_000):
                opponent = "BLACK" if player == "WHITE" else "WHITE"
                enc  = np.array(encode_board(board, player, cube_value, cube_owner), dtype=np.float32)
                v_np = net(torch.from_numpy(enc)).numpy().copy()
                can_double = (cube_owner is None or cube_owner == player) and cube_value < 64
                if can_double:
                    eq = float(np.dot(v_np, _W))
                    if eq > DOUBLE_THRESHOLD:
                        if eq > DROP_THRESHOLD:
                            experience.append((enc, win_target - v_np))
                            break
                        cube_value *= 2
                        cube_owner  = opponent
                        enc  = np.array(encode_board(board, player, cube_value, cube_owner), dtype=np.float32)
                        v_np = net(torch.from_numpy(enc)).numpy().copy()
                dice = roll_dice()
                best = _choose_1ply_cpu(board, dice, player, net, cube_value, cube_owner)
                if best is not None:
                    board = apply_move(board, best, player)
                winner, outcome = game_outcome(board)
                if winner is not None:
                    target = outcome_target(winner, outcome, player)
                    experience.append((enc, target - v_np))
                    break
                next_player = opponent
                next_enc = np.array(encode_board(board, next_player, cube_value, cube_owner), dtype=np.float32)
                v_new_np = net(torch.from_numpy(next_enc)).numpy().copy()
                experience.append((enc, -v_new_np - v_np))
                player = next_player
    return experience


def worker_fn(worker_id, task_queue, result_queue, hidden_size):
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
