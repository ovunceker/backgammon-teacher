import Foundation
import CoreML

// Uses the TDGammon CoreML model to pick the best legal move for a given board state.
struct AIPlayer {

    private static let model: TDGammon_875k? = {
        try? TDGammon_875k(configuration: MLModelConfiguration())
    }()

    // Decision depth for the AI's move search (PLAY TIME ONLY; training stays 0-ply).
    // 1 = static 1-ply choice, 2 = TD-Gammon-style 2-ply (default), 3 = deeper/slower.
    static let searchPlies = 2

    // All 21 distinct dice outcomes as Dice, weighted 2 for non-doubles / 1 for doubles
    // (sums to 36). Chance-node weights for the expectiminimax search.
    private static let all21Rolls: [(dice: Dice, weight: Float)] = {
        var out: [(Dice, Float)] = []
        for d1 in 1...6 {
            for d2 in d1...6 {
                out.append((Dice(d1, d2), d1 == d2 ? 1 : 2))
            }
        }
        return out
    }()

    // 6-output equity weights and the perspective-swap permutation. Vectors SWAP
    // (my_vec = opp_vec[swap]); only scalar equity negates. The model is only ever
    // queried on the side-about-to-roll's perspective — the same invariant as training.
    private static let W: [Float] = [1, 2, 3, -1, -2, -3]
    private static let swap: [Int] = [3, 4, 5, 0, 1, 2]

    // Returns equity and raw 6-probability array from `player`'s perspective.
    static func equityAndProbs(
        for state: BoardState,
        player: Player,
        cube: Int = 1,
        cubeOwner: Player? = nil
    ) -> (equity: Float, probs: [Float])? {
        guard let model else { return nil }
        let floats = BoardEncoder.encode(state, player: player, cube: cube, cubeOwner: cubeOwner)
        guard let input = try? MLMultiArray(shape: [1, 200], dataType: .float32) else { return nil }
        for (i, v) in floats.enumerated() { input[i] = NSNumber(value: v) }
        guard let output = try? model.prediction(x: input).output else { return nil }
        let weights: [Float] = [1, 2, 3, -1, -2, -3]
        var equity: Float = 0
        var probs = [Float](repeating: 0, count: 6)
        for i in 0..<6 {
            probs[i] = output[i].floatValue
            equity += weights[i] * probs[i]
        }
        return (equity, probs)
    }

    // (equity, probs) for `mover` of a position `mover` just moved into — i.e. the
    // OPPONENT is about to roll. Queries the model from the opponent's perspective
    // (training's "side about to roll" invariant), then swaps back to the mover's
    // frame: vectors swap, scalar equity == -oppEquity.
    static func equityAndProbsAfterMove(
        for state: BoardState,
        mover: Player,
        cube: Int = 1,
        cubeOwner: Player? = nil
    ) -> (equity: Float, probs: [Float])? {
        guard let (_, oppProbs) = equityAndProbs(for: state, player: mover.opponent,
                                                 cube: cube, cubeOwner: cubeOwner) else { return nil }
        let myProbs = swap.map { oppProbs[$0] }
        var equity: Float = 0
        for i in 0..<6 { equity += W[i] * myProbs[i] }
        return (equity, myProbs)
    }

    // Network equity from `player`'s perspective at the given state (no move applied).
    private static func evalEquity(state: BoardState, player: Player, cube: Int, cubeOwner: Player?) -> Float? {
        equityAndProbs(for: state, player: player, cube: cube, cubeOwner: cubeOwner)?.equity
    }

    // Probs from `perspective`'s view (perspective = the side about to roll).
    private static func rawProbs(for state: BoardState, perspective: Player) -> [Float]? {
        equityAndProbs(for: state, player: perspective)?.probs
    }

    // Dot the 6-vector with the equity weights.
    private static func equity(of probs: [Float]) -> Float {
        var e: Float = 0
        for i in 0..<6 { e += W[i] * probs[i] }
        return e
    }

    // Expected 6-vector outcome probs from `sideToRoll`'s perspective, looking `plies`
    // half-moves ahead. plies == 0 → a single static model query. Chance nodes average
    // over the 21 rolls; decision nodes pick the mover's best move. Vectors swap down
    // the tree (child is the opponent's view); only scalar equity negates.
    // SEARCH IS PLAY-TIME ONLY — never used in the training loop.
    static func expectedProbs(_ state: BoardState, sideToRoll: Player, plies: Int) -> [Float]? {
        if plies == 0 { return rawProbs(for: state, perspective: sideToRoll) }
        var acc = [Float](repeating: 0, count: 6)
        for (dice, weight) in all21Rolls {
            var s = state
            s.currentPlayer = sideToRoll
            let moves = MoveGenerator.legalMoves(for: s, dice: dice)
            var bestVec: [Float]
            if moves.isEmpty {
                // Dance: turn passes to the opponent, board unchanged.
                guard let child = expectedProbs(s, sideToRoll: sideToRoll.opponent, plies: plies - 1)
                else { return nil }
                bestVec = swap.map { child[$0] }
            } else {
                var bestEq = -Float.greatestFiniteMagnitude
                bestVec = [Float](repeating: 0, count: 6)
                for m in moves {
                    var next = s
                    for step in m { next = next.applying(step) }
                    guard let child = expectedProbs(next, sideToRoll: sideToRoll.opponent, plies: plies - 1)
                    else { continue }
                    let mine = swap.map { child[$0] }   // child is opponent's view; swap to sideToRoll's
                    let eq = equity(of: mine)
                    if eq > bestEq { bestEq = eq; bestVec = mine }
                }
            }
            for i in 0..<6 { acc[i] += weight * bestVec[i] }
        }
        return acc.map { $0 / 36 }
    }

    // When black is safely bearing off (no white pieces in black's home board or on
    // white's bar), restrict candidates to moves that bear off at least one checker.
    private static func bearOffFiltered(_ moves: [Move], state: BoardState) -> [Move] {
        guard state.currentPlayer == .black else { return moves }
        // Black must have all checkers on points 19-24 (none at 1-18 or on black's bar).
        guard (1...18).allSatisfy({ state.points[$0] >= 0 }),
              state.blackBar == 0
        else { return moves }
        // White must have no checkers in black's home (19-24) or on white's bar.
        guard (19...24).allSatisfy({ state.points[$0] <= 0 }),
              state.whiteBar == 0
        else { return moves }
        // Tier 1: moves whose first step immediately bears off.
        let immediate = moves.filter { $0.first?.to == 25 }
        if !immediate.isEmpty { return immediate }
        // Tier 2: moves that bear off in some later step (die-order constraint).
        let anyBearOff = moves.filter { move in move.contains { $0.to == 25 } }
        return anyBearOff.isEmpty ? moves : anyBearOff
    }

    // n-ply expectiminimax move choice (default `searchPlies`). Pre-scores every
    // candidate with a 1-ply static eval, keeps a survivor set (top K plus any within
    // 0.08 equity of the best), then deep-searches only the survivors. plies <= 1
    // reproduces the static 1-ply choice.
    static func bestMove(for state: BoardState, moves: [Move], cube: Int = 1, cubeOwner: Player? = nil) -> Move? {
        guard model != nil, !moves.isEmpty else { return nil }
        let player = state.currentPlayer
        let moves = bearOffFiltered(moves, state: state)
        let opponent = player.opponent
        let plies = searchPlies

        // Ply-1 static pre-score of every candidate.
        var scored: [(move: Move, next: BoardState, eq1: Float)] = []
        for move in moves {
            var next = state
            for step in move { next = next.applying(step) }
            guard let (eq, _) = equityAndProbsAfterMove(for: next, mover: player,
                                                        cube: cube, cubeOwner: cubeOwner) else { continue }
            scored.append((move, next, eq))
        }
        guard !scored.isEmpty else { return moves.first }
        scored.sort { $0.eq1 > $1.eq1 }
        if plies <= 1 { return scored.first!.move }

        // Survivor set: top K plus any near-tie within 0.08 equity of the best.
        let K = 5
        let bestEq1 = scored.first!.eq1
        var survivors = Array(scored.prefix(K))
        for s in scored.dropFirst(K) where bestEq1 - s.eq1 <= 0.08 { survivors.append(s) }

        var choice = survivors.first!.move
        var bestEq = -Float.greatestFiniteMagnitude
        for cand in survivors {
            guard let child = expectedProbs(cand.next, sideToRoll: opponent, plies: plies - 1)
            else { continue }
            let eq = equity(of: swap.map { child[$0] })
            if eq > bestEq { bestEq = eq; choice = cand.move }
        }
        return choice
    }

    // Evaluates the current position equity from state.currentPlayer's perspective.
    static func rawEquity(for state: BoardState, cube: Int = 1, cubeOwner: Player? = nil) -> Float? {
        evalEquity(state: state, player: state.currentPlayer, cube: cube, cubeOwner: cubeOwner)
    }
}
