import Foundation

// A single checker's movement for one die value.
struct CheckerMove: Hashable {
    let from: Int   // 1-24, or player.barPoint for bar re-entry
    let to: Int     // 1-24, or player.boreOffPoint for bearing off
    let die: Int
}

// A complete turn: up to 2 CheckerMoves (or 4 for doubles).
typealias Move = [CheckerMove]

// MARK: - MoveGenerator

struct MoveGenerator {

    // Returns all distinct legal complete moves for the current player.
    // "Distinct" means unique resulting board states.
    static func legalMoves(for state: BoardState, dice: Dice) -> [Move] {
        var results: [(move: Move, finalState: BoardState)] = []
        generate(state: state, remainingDice: dice.remaining, current: [], results: &results)

        guard let maxUsed = results.map(\.move.count).max(), maxUsed > 0 else { return [] }

        var candidates = results.filter { $0.move.count == maxUsed }

        // Backgammon rule: if only 1 of 2 distinct dice can be played, must use the higher one.
        if maxUsed == 1 && dice.values.count == 2 && dice.values[0] != dice.values[1] {
            let higher = max(dice.values[0], dice.values[1])
            let withHigher = candidates.filter { $0.move.first?.die == higher }
            if !withHigher.isEmpty { candidates = withHigher }
        }

        // Deduplicate by resulting board state so the UI never shows identical outcomes.
        var seen = Set<BoardState>()
        return candidates.compactMap { pair in
            seen.insert(pair.finalState).inserted ? pair.move : nil
        }
    }

    // MARK: Recursive builder

    private static func generate(
        state: BoardState,
        remainingDice: [Int],
        current: Move,
        results: inout [(move: Move, finalState: BoardState)]
    ) {
        let singles = singleMoves(for: state, dice: remainingDice)
        guard !singles.isEmpty else {
            results.append((current, state))
            return
        }
        var triedDice = Set<Int>()
        for die in remainingDice {
            guard triedDice.insert(die).inserted else { continue }
            let movesForDie = singles.filter { $0.die == die }
            guard !movesForDie.isEmpty else { continue }
            var nextDice = remainingDice
            nextDice.remove(at: nextDice.firstIndex(of: die)!)
            for m in movesForDie {
                generate(
                    state: state.applying(m),
                    remainingDice: nextDice,
                    current: current + [m],
                    results: &results
                )
            }
        }
    }

    // MARK: Single-checker move generation

    // All valid single-checker moves the current player can make with any of `dice`.
    private static func singleMoves(for state: BoardState, dice: [Int]) -> [CheckerMove] {
        let player = state.currentPlayer
        var moves: [CheckerMove] = []
        for die in Set(dice) {
            if state.barCount(for: player) > 0 {
                // Must re-enter from bar before moving any board checker.
                let to = player.barPoint + player.direction * die
                if !state.isBlocked(at: to, for: player) {
                    moves.append(CheckerMove(from: player.barPoint, to: to, die: die))
                }
            } else {
                for pt in 1...24 where state.checkerCount(at: pt, for: player) > 0 {
                    let dest = pt + player.direction * die
                    if (1...24).contains(dest) {
                        if !state.isBlocked(at: dest, for: player) {
                            moves.append(CheckerMove(from: pt, to: dest, die: die))
                        }
                    } else if state.canBearOff(player: player),
                              isBearOffLegal(from: pt, dest: dest, player: player, in: state) {
                        moves.append(CheckerMove(from: pt, to: player.boreOffPoint, die: die))
                    }
                }
            }
        }
        return moves
    }

    // MARK: Bear-off legality

    // Exact bear-off (dest == boreOffPoint) is always legal when canBearOff is true.
    // Overshoot bear-off is only legal when no friendly checker sits on a point farther from home.
    private static func isBearOffLegal(
        from point: Int, dest: Int, player: Player, in state: BoardState
    ) -> Bool {
        if player == .white {
            // White moves toward 1; "farther from home" means higher-numbered points in 1-6.
            return dest == 0
                || (1...6).filter { $0 > point }.allSatisfy { state.checkerCount(at: $0, for: .white) == 0 }
        } else {
            // Black moves toward 24; "farther from home" means lower-numbered points in 19-24.
            return dest == 25
                || (19...24).filter { $0 < point }.allSatisfy { state.checkerCount(at: $0, for: .black) == 0 }
        }
    }
}
