import Foundation
import CoreML

// Uses the TDGammon CoreML model to pick the best legal move for a given board state.
struct AIPlayer {

    private static let model: TDGammon? = {
        try? TDGammon(configuration: MLModelConfiguration())
    }()

    // Returns the index into `moves` of the highest-equity move, or nil if inference fails.
    static func bestMove(for state: BoardState, moves: [Move], cube: Int = 1, cubeOwner: Player? = nil) -> Move? {
        guard let model, !moves.isEmpty else { return nil }
        let player = state.currentPlayer

        var bestMove: Move? = nil
        var bestEquity: Float = -.greatestFiniteMagnitude

        for move in moves {
            // Apply the full move to get the resulting position
            var next = state
            for step in move { next = next.applying(step) }

            // Encode from the current player's perspective
            let floats = BoardEncoder.encode(next, player: player, cube: cube, cubeOwner: cubeOwner)

            guard let input = try? MLMultiArray(shape: [1, 200], dataType: .float32) else { continue }
            for (i, v) in floats.enumerated() { input[i] = NSNumber(value: v) }

            guard let output = try? model.prediction(x: input).output else { continue }

            // Equity = dot([1,2,3,-1,-2,-3], output) — mirrors choose_move() in Python
            let weights: [Float] = [1, 2, 3, -1, -2, -3]
            var equity: Float = 0
            for i in 0..<6 { equity += weights[i] * output[i].floatValue }

            if equity > bestEquity {
                bestEquity = equity
                bestMove   = move
            }
        }

        return bestMove
    }

    // Evaluates the current position equity from state.currentPlayer's perspective.
    static func rawEquity(for state: BoardState, cube: Int = 1, cubeOwner: Player? = nil) -> Float? {
        guard let model else { return nil }
        let player = state.currentPlayer
        let floats = BoardEncoder.encode(state, player: player, cube: cube, cubeOwner: cubeOwner)
        guard let input = try? MLMultiArray(shape: [1, 200], dataType: .float32) else { return nil }
        for (i, v) in floats.enumerated() { input[i] = NSNumber(value: v) }
        guard let output = try? model.prediction(x: input).output else { return nil }
        let weights: [Float] = [1, 2, 3, -1, -2, -3]
        var equity: Float = 0
        for i in 0..<6 { equity += weights[i] * output[i].floatValue }
        return equity
    }
}
