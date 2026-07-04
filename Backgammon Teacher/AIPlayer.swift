import Foundation
import CoreML

// Uses the TDGammon CoreML model to pick the best legal move for a given board state.
struct AIPlayer {

    private static let model: TDGammon? = {
        try? TDGammon(configuration: MLModelConfiguration())
    }()

    // All 21 distinct dice outcomes. Non-doubles have weight 2, doubles weight 1 (out of 36 total).
    private static let allDice: [(d1: Int, d2: Int, weight: Int)] = {
        var outcomes: [(Int, Int, Int)] = []
        for d1 in 1...6 {
            for d2 in d1...6 {
                outcomes.append((d1, d2, d1 == d2 ? 1 : 2))
            }
        }
        return outcomes
    }()

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

    // Network equity from `player`'s perspective at the given state (no move applied).
    private static func evalEquity(state: BoardState, player: Player, cube: Int, cubeOwner: Player?) -> Float? {
        equityAndProbs(for: state, player: player, cube: cube, cubeOwner: cubeOwner)?.equity
    }

    // 1-ply: pick the move with the highest equity from `player`'s perspective.
    // Returns the best move and its resulting board state, or nil on failure.
    private static func best1Ply(
        moves: [Move],
        state: BoardState,
        player: Player,
        cube: Int,
        cubeOwner: Player?
    ) -> (move: Move, next: BoardState, equity: Float)? {
        guard !moves.isEmpty else { return nil }
        var best: (move: Move, next: BoardState, equity: Float)? = nil
        for move in moves {
            var next = state
            for step in move { next = next.applying(step) }
            guard let eq = evalEquity(state: next, player: player, cube: cube, cubeOwner: cubeOwner) else { continue }
            if best == nil || eq > best!.equity { best = (move, next, eq) }
        }
        return best
    }

    // 3-ply search with forward pruning — mirrors choose_move() in Python.
    // K=5 candidate moves kept after ply-1 pre-filter.
    // J=3 opponent moves kept after ply-2 pruning.
    // Ply-3 is a full 21-outcome expectation from the leaf.
    static func bestMove(for state: BoardState, moves: [Move], cube: Int = 1, cubeOwner: Player? = nil) -> Move? {
        guard let model, !moves.isEmpty else { return nil }
        let player = state.currentPlayer
        let K = 5
        let J = 3

        // --- Ply 1: score each candidate by 1-ply equity, keep top K ---
        var scored: [(move: Move, next: BoardState, eq1: Float)] = []
        for move in moves {
            var next = state
            for step in move { next = next.applying(step) }
            guard let eq = evalEquity(state: next, player: player, cube: cube, cubeOwner: cubeOwner) else { continue }
            scored.append((move, next, eq))
        }
        guard !scored.isEmpty else { return moves.first }
        scored.sort { $0.eq1 > $1.eq1 }
        let candidates = Array(scored.prefix(K))

        let opponent = player.opponent
        var bestFinalEquity: Float = -.greatestFiniteMagnitude
        var bestMove: Move? = candidates.first?.move

        for candidate in candidates {
            // After applying our move, it's the opponent's turn.
            var oppState = candidate.next
            oppState.currentPlayer = opponent

            // --- Ply 2: average over opponent dice, keep J best opponent responses ---
            // For each dice outcome, find the opponent's best 1-ply reply.
            // Score from opponent's perspective, then take the J outcomes that hurt us most.
            var ply2Samples: [(weight: Int, oppNext: BoardState, oppEq: Float)] = []

            for (d1, d2, weight) in allDice {
                let oppDice = Dice(d1, d2)
                let oppMoves = MoveGenerator.legalMoves(for: oppState, dice: oppDice)
                if oppMoves.isEmpty {
                    // Opponent has no moves — their state passes unchanged
                    ply2Samples.append((weight, oppState, 0))
                    continue
                }
                guard let oppBest = best1Ply(moves: oppMoves, state: oppState,
                                             player: opponent, cube: cube, cubeOwner: cubeOwner)
                else { continue }
                // oppBest.equity is from opponent's view; higher = worse for us
                ply2Samples.append((weight, oppBest.next, oppBest.equity))
            }

            // Prune to J outcomes that are best for the opponent (worst for us)
            let pruned = ply2Samples.sorted { $0.oppEq > $1.oppEq }.prefix(J)

            // --- Ply 3: for each pruned opponent reply, expectimax over our dice ---
            var weightedEquitySum: Float = 0
            var weightedEquityTotal: Float = 0

            for sample in pruned {
                var myState = sample.oppNext
                myState.currentPlayer = player

                var ply3Sum: Float = 0
                var ply3Total: Float = 0

                for (d1, d2, weight) in allDice {
                    let myDice = Dice(d1, d2)
                    let myMoves = MoveGenerator.legalMoves(for: myState, dice: myDice)
                    let w = Float(weight)
                    if myMoves.isEmpty {
                        // No moves; evaluate state as-is
                        let eq = evalEquity(state: myState, player: player, cube: cube, cubeOwner: cubeOwner) ?? 0
                        ply3Sum   += w * eq
                        ply3Total += w
                        continue
                    }
                    // Pick best leaf move by 1-ply
                    if let leafBest = best1Ply(moves: myMoves, state: myState,
                                               player: player, cube: cube, cubeOwner: cubeOwner) {
                        ply3Sum   += w * leafBest.equity
                        ply3Total += w
                    }
                }

                let ply3Equity = ply3Total > 0 ? ply3Sum / ply3Total : 0
                let sw = Float(sample.weight)
                weightedEquitySum   += sw * ply3Equity
                weightedEquityTotal += sw
            }

            let finalEquity = weightedEquityTotal > 0 ? weightedEquitySum / weightedEquityTotal : 0
            if finalEquity > bestFinalEquity {
                bestFinalEquity = finalEquity
                bestMove = candidate.move
            }
        }

        return bestMove
    }

    // Evaluates the current position equity from state.currentPlayer's perspective.
    static func rawEquity(for state: BoardState, cube: Int = 1, cubeOwner: Player? = nil) -> Float? {
        evalEquity(state: state, player: state.currentPlayer, cube: cube, cubeOwner: cubeOwner)
    }
}
