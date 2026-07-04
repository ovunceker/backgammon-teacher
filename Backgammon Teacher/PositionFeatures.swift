import Foundation

// MARK: - Blot

/// A single exposed checker (exactly 1 checker on a point).
struct Blot: Equatable {
    let point: Int
    /// Opponent dice rolls (out of 36) that can hit this blot.
    let shotCount: Int
}

// MARK: - PositionFeatures

/// Board features extracted from one player's perspective.
/// In practice always computed for .white (the human), but generic.
struct PositionFeatures {
    let blots: [Blot]                   // exposed checkers (exactly 1 on the point)
    let pointsMade: Set<Int>            // points held with 2+ checkers
    let pipCount: Int
    let opponentPipCount: Int
    let primeLength: Int                // longest run of consecutive made points
    let primeInFrontOfOpponent: Bool    // prime is positioned in front of opponent back checkers
    let homeBoardPoints: Int            // made points inside own home board
    let anchors: Set<Int>               // made points inside opponent's home board
    let maxStack: Int                   // largest checker count on a single point
    let checkersInOpponentHome: Int     // player's checkers still inside opponent's home board
    let isBearingOff: Bool
    let isContactBroken: Bool           // pure race: no mutual contact possible

    init(state: BoardState, player: Player) {
        let opponent = player.opponent

        // ── Blots, made points, max stack ─────────────────────────────────────
        var blotPoints: [Int] = []
        var made = Set<Int>()
        var stackMax = 0

        for p in 1...24 {
            let count = state.checkerCount(at: p, for: player)
            switch count {
            case 1:  blotPoints.append(p)
            case 2...: made.insert(p)
            default: break
            }
            stackMax = max(stackMax, count)
        }

        // Shot counting: evaluate from the opponent's perspective on this board.
        var opponentState = state
        opponentState.currentPlayer = opponent
        self.blots = blotPoints.map { p in
            Blot(point: p, shotCount: Self.countShots(to: p, opponentState: opponentState))
        }
        self.pointsMade = made
        self.maxStack = stackMax

        // ── Pip counts ────────────────────────────────────────────────────────
        self.pipCount = Self.computePip(state: state, player: player)
        self.opponentPipCount = Self.computePip(state: state, player: opponent)

        // ── Prime: longest consecutive run of made points ─────────────────────
        let sortedMade = made.sorted()
        var primeLen = 0
        var primeLow = 1
        var primeHigh = 0

        if !sortedMade.isEmpty {
            var curStart = sortedMade[0]
            var curLen = 1

            for i in 1..<sortedMade.count {
                if sortedMade[i] == sortedMade[i - 1] + 1 {
                    curLen += 1
                } else {
                    if curLen > primeLen {
                        primeLen = curLen
                        primeLow = curStart
                        primeHigh = sortedMade[i - 1]
                    }
                    curStart = sortedMade[i]
                    curLen = 1
                }
            }
            if curLen > primeLen {
                primeLen = curLen
                primeLow = curStart
                primeHigh = sortedMade[sortedMade.count - 1]
            }
        }

        self.primeLength = primeLen

        // ── Prime in front of opponent (requires length >= 2) ─────────────────
        if primeLen >= 2 {
            if player == .white {
                // Black moves 1→24; back checkers at low points are trapped.
                let hasTrapped = primeLow > 1 &&
                    (1..<primeLow).contains { state.checkerCount(at: $0, for: opponent) > 0 }
                // Bar checkers enter at 1–6; blocked if the prime starts past 6.
                let barTrapped = state.barCount(for: opponent) > 0 && primeLow > 6
                self.primeInFrontOfOpponent = hasTrapped || barTrapped
            } else {
                // White moves 24→1; back checkers at high points are trapped.
                let hasTrapped = primeHigh < 24 &&
                    ((primeHigh + 1)...24).contains { state.checkerCount(at: $0, for: opponent) > 0 }
                // Bar checkers enter at 19–24; blocked if the prime ends before 19.
                let barTrapped = state.barCount(for: opponent) > 0 && primeHigh < 19
                self.primeInFrontOfOpponent = hasTrapped || barTrapped
            }
        } else {
            self.primeInFrontOfOpponent = false
        }

        // ── Home board points and anchors ─────────────────────────────────────
        self.homeBoardPoints = player.homeRange.filter { made.contains($0) }.count
        self.anchors = made.filter { opponent.homeRange.contains($0) }

        // ── Checkers still in opponent's home ─────────────────────────────────
        self.checkersInOpponentHome = opponent.homeRange.reduce(0) {
            $0 + state.checkerCount(at: $1, for: player)
        }

        // ── Bearing off ───────────────────────────────────────────────────────
        self.isBearingOff = state.canBearOff(player: player)

        // ── Contact broken (pure race) ────────────────────────────────────────
        // No bar checkers, and the highest white point < lowest black point.
        let maxWhitePoint = (1...24).filter { state.points[$0] > 0 }.max() ?? 0
        let minBlackPoint = (1...24).filter { state.points[$0] < 0 }.min() ?? 25
        self.isContactBroken = state.whiteBar == 0 && state.blackBar == 0
            && maxWhitePoint < minBlackPoint
    }

    // MARK: - Pip count

    /// White: Σ(checkerCount × pointIndex) + barCheckers × 25.
    /// Black: Σ(checkerCount × (25 − pointIndex)) + barCheckers × 25.
    static func computePip(state: BoardState, player: Player) -> Int {
        if player == .white {
            var total = state.whiteBar * 25
            for p in 1...24 where state.points[p] > 0 {
                total += state.points[p] * p
            }
            return total
        } else {
            var total = state.blackBar * 25
            for p in 1...24 where state.points[p] < 0 {
                total += (-state.points[p]) * (25 - p)
            }
            return total
        }
    }

    // MARK: - Shot counting

    /// Returns the number of the 36 opponent dice rolls that can hit a blot at `point`.
    ///
    /// Iterates all 21 distinct outcomes (non-doubles weighted ×2, doubles ×1) and
    /// delegates to MoveGenerator to handle blocking, bar entry, and doubles correctly.
    /// `opponentState` must have `currentPlayer` set to the opponent.
    private static func countShots(to point: Int, opponentState: BoardState) -> Int {
        var total = 0
        for d1 in 1...6 {
            for d2 in d1...6 {
                let weight = d1 == d2 ? 1 : 2
                let moves = MoveGenerator.legalMoves(for: opponentState, dice: Dice(d1, d2))
                if moves.contains(where: { move in move.contains { $0.to == point } }) {
                    total += weight
                }
            }
        }
        return total
    }
}
