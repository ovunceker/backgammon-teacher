import Foundation

enum Player: Hashable {
    case white, black

    var opponent: Player { self == .white ? .black : .white }

    // White re-enters from "point 25" (25 - die lands in black's home 19-24).
    // Black re-enters from "point 0"  (0  + die lands in white's home 1-6).
    var barPoint: Int { self == .white ? 25 : 0 }

    // White bears off to "point 0", black bears off to "point 25".
    var boreOffPoint: Int { self == .white ? 0 : 25 }

    var homeRange: ClosedRange<Int> { self == .white ? 1...6 : 19...24 }

    // Direction of travel on the number line.
    var direction: Int { self == .white ? -1 : 1 }
}

// MARK: - BoardState

struct BoardState: Hashable {

    // points[1..24]: positive = white checker count, negative = black checker count.
    // points[0] and points[25] are unused padding; bars are tracked separately.
    var points: [Int]         // 26 elements

    var whiteBar: Int
    var blackBar: Int
    var whiteBorneOff: Int
    var blackBorneOff: Int
    var currentPlayer: Player

    // MARK: Factory

    static func makeInitial() -> BoardState {
        var pts = [Int](repeating: 0, count: 26)
        // White checkers (positive values)
        pts[24] = 2; pts[13] = 5; pts[8] = 3; pts[6] = 5
        // Black checkers (negative values)
        pts[1] = -2; pts[12] = -5; pts[17] = -3; pts[19] = -5
        return BoardState(
            points: pts,
            whiteBar: 0, blackBar: 0,
            whiteBorneOff: 0, blackBorneOff: 0,
            currentPlayer: .white
        )
    }

    // MARK: Queries

    func checkerCount(at point: Int, for player: Player) -> Int {
        player == .white ? max(0, points[point]) : max(0, -points[point])
    }

    func barCount(for player: Player) -> Int {
        player == .white ? whiteBar : blackBar
    }

    // True if `player` cannot land on `point` (opponent holds it with 2+ checkers).
    func isBlocked(at point: Int, for player: Player) -> Bool {
        player == .white ? points[point] <= -2 : points[point] >= 2
    }

    // True when all of `player`'s remaining checkers are in the home board.
    func canBearOff(player: Player) -> Bool {
        if player == .white {
            return whiteBar == 0 && (7...24).allSatisfy { points[$0] <= 0 }
        } else {
            return blackBar == 0 && (1...18).allSatisfy { points[$0] >= 0 }
        }
    }

    var winner: Player? {
        if whiteBorneOff == 15 { return .white }
        if blackBorneOff == 15 { return .black }
        return nil
    }

    // MARK: State transition

    func applying(_ move: CheckerMove) -> BoardState {
        var s = self
        // d = +1 for white (points are positive), -1 for black (points are negative).
        let d = currentPlayer == .white ? 1 : -1

        // Remove checker from source.
        if move.from == currentPlayer.barPoint {
            if currentPlayer == .white { s.whiteBar -= 1 } else { s.blackBar -= 1 }
        } else {
            s.points[move.from] -= d
        }

        // Place checker at destination.
        if move.to == currentPlayer.boreOffPoint {
            if currentPlayer == .white { s.whiteBorneOff += 1 } else { s.blackBorneOff += 1 }
        } else {
            // Hit: exactly one opponent checker on the landing point.
            if s.points[move.to] == -d {
                s.points[move.to] = 0
                if currentPlayer == .white { s.blackBar += 1 } else { s.whiteBar += 1 }
            }
            s.points[move.to] += d
        }

        return s
    }
}
