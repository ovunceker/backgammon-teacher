import Foundation

// MARK: - ErrorSeverity

enum ErrorSeverity: Equatable {
    case fine         // gap < 0.02
    case inaccuracy   // 0.02 ..< 0.08
    case error        // 0.08 ..< 0.15
    case blunder      // >= 0.15
}

// MARK: - ExplanationReason

enum ExplanationReason: Equatable {
    case missedHit(point: Int)
    case exposureDifference
    case unnecessaryBlot
    case badHit
    case missedPoint(point: Int, isGoldenPoint: Bool)
    case racingDecision
    case primeDifference
    case brokenAnchor
    case bearOffSafety
    case overstacking
    case homeBoardWeakened
    case outcomeTradeoff
    case generallyBetter
}

// MARK: - MoveAlternative

struct MoveAlternative {
    let move: Move
    let finalState: BoardState
    let equity: Float
    var dice: (Int, Int)? = nil   // set for opponent responses
}

// MARK: - MoveAnalysis

struct MoveAnalysis {
    let playerEquity: Float
    let bestEquity: Float
    let bestMove: Move
    let severity: ErrorSeverity
    let reasons: [ExplanationReason]
    let playerProbs: [Float]
    let bestProbs: [Float]
    // Board context for detailed explanation sheet
    let preTurnState: BoardState
    let playerFinalState: BoardState
    let bestFinalState: BoardState
    let dice: Dice
    let playerShotsAgainstBlots: Int   // # of 36 rolls that can hit white after player's move
    let bestShotsAgainstBlots: Int     // # of 36 rolls that can hit white after best move
    let playerShotsByZone: [Int]       // [blackHome(19-24), blackOuter(13-18), whiteOuter(7-12), whiteHome(1-6)]
    let topOpponentResponses: [MoveAlternative]  // up to 4, probability-weighted, sorted
    let topAlternatives: [MoveAlternative]       // up to 4 better moves, sorted best-first
}

// MARK: - MoveExplainer

struct MoveExplainer {

    // MARK: - Public API

    /// Analyze a completed human turn. Returns nil if the model is unavailable or no legal moves exist.
    /// - Parameters:
    ///   - preTurnState: Board state before the human moved (currentPlayer = .white, all dice remaining).
    ///   - dice: Dice for this turn.
    ///   - playerFinalState: Board state after all the human's moves.
    static func analyze(
        preTurnState: BoardState,
        dice: Dice,
        playerFinalState: BoardState
    ) -> MoveAnalysis? {
        let player = Player.white

        let freshDice = dice.isDoubles
            ? Dice(dice.values[0], dice.values[0])
            : Dice(dice.values[0], dice.values[1])

        let moves = MoveGenerator.legalMoves(for: preTurnState, dice: freshDice)
        guard !moves.isEmpty else { return nil }

        var best: (move: Move, state: BoardState, equity: Float, probs: [Float])?
        var playerResult: (equity: Float, probs: [Float])?
        var allMoveResults: [(move: Move, state: BoardState, equity: Float)] = []

        for move in moves {
            var next = preTurnState
            for step in move { next = next.applying(step) }
            guard let (eq, probs) = AIPlayer.equityAndProbsAfterMove(for: next, mover: player) else { continue }

            if boardsMatch(next, playerFinalState) {
                playerResult = (eq, probs)
            }
            if best == nil || eq > best!.equity {
                best = (move, next, eq, probs)
            }
            allMoveResults.append((move, next, eq))
        }

        guard let bestResult = best,
              let (playerEquity, playerProbs) = playerResult else { return nil }

        let playerShotsAgainstBlots = countHittingRolls(against: playerFinalState)
        let bestShotsAgainstBlots   = countHittingRolls(against: bestResult.state)
        let playerShotsByZone       = countHittingRollsByZone(against: playerFinalState)

        // Collect up to 4 distinct better moves (different final state, higher equity)
        var seenStates: [BoardState] = []
        var topAlts: [MoveAlternative] = []
        for r in allMoveResults.sorted(by: { $0.equity > $1.equity }) {
            guard r.equity > playerEquity, !boardsMatch(r.state, playerFinalState) else { continue }
            guard !seenStates.contains(where: { boardsMatch($0, r.state) }) else { continue }
            topAlts.append(MoveAlternative(move: r.move, finalState: r.state, equity: r.equity))
            seenStates.append(r.state)
            if topAlts.count == 4 { break }
        }

        let gap = bestResult.equity - playerEquity
        let sev = severity(for: gap)
        let reasons = detectReasons(
            preTurnState: preTurnState,
            playerState: playerFinalState,
            bestState: bestResult.state,
            playerProbs: playerProbs,
            bestProbs: bestResult.probs
        )

        // Find opponent's most threatening response to the player's move (1-ply, all 21 rolls)
        // For each of the 21 dice rolls find the best move, then rank rolls by
        // probability-weighted equity so doubles (1/36) don't always dominate (2/36).
        var oppBase = playerFinalState
        oppBase.currentPlayer = .black
        var rollEntries: [(d1: Int, d2: Int, move: Move, state: BoardState, equity: Float, weighted: Float)] = []
        for d1 in 1...6 {
            for d2 in d1...6 {
                let prob: Float = d1 == d2 ? 1.0 : 2.0
                let roll = Dice(d1, d2)
                let oppMoves = MoveGenerator.legalMoves(for: oppBase, dice: roll)
                var bestEq = -Float.greatestFiniteMagnitude
                var bestM: Move? = nil
                var bestS: BoardState? = nil
                for m in oppMoves {
                    var next = oppBase
                    for step in m { next = next.applying(step) }
                    if let (eq, _) = AIPlayer.equityAndProbsAfterMove(for: next, mover: .black), eq > bestEq {
                        bestEq = eq; bestM = m; bestS = next
                    }
                }
                if let m = bestM, let s = bestS {
                    rollEntries.append((d1, d2, m, s, bestEq, bestEq * prob))
                }
            }
        }
        rollEntries.sort { $0.weighted > $1.weighted }
        var seenOppStates: [BoardState] = []
        var topOppResponses: [MoveAlternative] = []
        for r in rollEntries {
            guard !seenOppStates.contains(where: { boardsMatch($0, r.state) }) else { continue }
            topOppResponses.append(MoveAlternative(move: r.move, finalState: r.state, equity: r.equity, dice: (r.d1, r.d2)))
            seenOppStates.append(r.state)
            if topOppResponses.count == 4 { break }
        }

        return MoveAnalysis(
            playerEquity: playerEquity,
            bestEquity: bestResult.equity,
            bestMove: bestResult.move,
            severity: sev,
            reasons: reasons,
            playerProbs: playerProbs,
            bestProbs: bestResult.probs,
            preTurnState: preTurnState,
            playerFinalState: playerFinalState,
            bestFinalState: bestResult.state,
            dice: freshDice,
            playerShotsAgainstBlots: playerShotsAgainstBlots,
            bestShotsAgainstBlots: bestShotsAgainstBlots,
            playerShotsByZone: playerShotsByZone,
            topOpponentResponses: topOppResponses,
            topAlternatives: topAlts
        )
    }

    // MARK: - Severity

    static func severity(for gap: Float) -> ErrorSeverity {
        switch gap {
        case ..<0.02:   return .fine
        case 0.02..<0.08: return .inaccuracy
        case 0.08..<0.15: return .error
        default:          return .blunder
        }
    }

    // MARK: - Reason detection

    static func detectReasons(
        preTurnState: BoardState,
        playerState: BoardState,
        bestState: BoardState,
        playerProbs: [Float],
        bestProbs: [Float]
    ) -> [ExplanationReason] {
        let player = Player.white
        let preTurnFeatures = PositionFeatures(state: preTurnState, player: player)
        let playerFeatures  = PositionFeatures(state: playerState,  player: player)
        let bestFeatures    = PositionFeatures(state: bestState,    player: player)

        var reasons: [ExplanationReason] = []

        // missedHit: opponent had a blot; best hit it; player didn't
        for p in 1...24 {
            if preTurnState.points[p] == -1
                && bestState.points[p] >= 1
                && playerState.points[p] == -1 {
                reasons.append(.missedHit(point: p))
            }
        }

        // unnecessaryBlot: player left a blot, best didn't
        if !playerFeatures.blots.isEmpty && bestFeatures.blots.isEmpty {
            reasons.append(.unnecessaryBlot)
        }

        // exposureDifference: both have blots, player's worst is significantly more exposed
        if !playerFeatures.blots.isEmpty && !bestFeatures.blots.isEmpty {
            let playerWorst = playerFeatures.blots.map(\.shotCount).max() ?? 0
            let bestWorst   = bestFeatures.blots.map(\.shotCount).max() ?? 0
            if playerWorst - bestWorst >= 6 {
                reasons.append(.exposureDifference)
            }
        }

        // badHit: player hit a blot but created more dangerous exposure than best
        let playerHits = (1...24).filter { p in
            preTurnState.points[p] == -1 && playerState.points[p] == 1
        }
        if !playerHits.isEmpty {
            let playerMaxShots = playerFeatures.blots.map(\.shotCount).max() ?? 0
            let bestMaxShots   = bestFeatures.blots.map(\.shotCount).max() ?? 0
            if playerMaxShots > bestMaxShots && playerMaxShots >= 12 {
                reasons.append(.badHit)
            }
        }

        // missedPoint: best made a point that player didn't, and it wasn't already made
        for p in bestFeatures.pointsMade
            where !playerFeatures.pointsMade.contains(p) && !preTurnFeatures.pointsMade.contains(p) {
            let isGolden = (p == 5 || p == 7 || p == 20)
            reasons.append(.missedPoint(point: p, isGoldenPoint: isGolden))
        }

        // racingDecision: pure race position
        if preTurnFeatures.isContactBroken || playerFeatures.isContactBroken {
            reasons.append(.racingDecision)
        }

        // primeDifference: best built a longer prime
        if bestFeatures.primeLength > playerFeatures.primeLength {
            reasons.append(.primeDifference)
        }

        // brokenAnchor: player gave up an anchor that best kept
        let lostAnchors = preTurnFeatures.anchors.subtracting(playerFeatures.anchors)
        let bestAlsoLost = preTurnFeatures.anchors.subtracting(bestFeatures.anchors)
        let unnecessarilyLost = lostAnchors.subtracting(bestAlsoLost)
        if !unnecessarilyLost.isEmpty {
            reasons.append(.brokenAnchor)
        }

        // bearOffSafety: in bearing-off phase, player left more blots than best
        if preTurnFeatures.isBearingOff && playerFeatures.blots.count > bestFeatures.blots.count {
            reasons.append(.bearOffSafety)
        }

        // overstacking: player stacked 2+ more checkers on one point than best
        if playerFeatures.maxStack >= bestFeatures.maxStack + 2 {
            reasons.append(.overstacking)
        }

        // homeBoardWeakened: player ended with fewer made home-board points
        if playerFeatures.homeBoardPoints < bestFeatures.homeBoardPoints {
            reasons.append(.homeBoardWeakened)
        }

        // outcomeTradeoff: significant gammon probability difference
        if playerProbs.count == 6 && bestProbs.count == 6 {
            let gammonWinDiff  = bestProbs[1] - playerProbs[1]
            let gammonRiskDiff = playerProbs[4] - bestProbs[4]
            if abs(gammonWinDiff) > 0.04 || abs(gammonRiskDiff) > 0.04 {
                reasons.append(.outcomeTradeoff)
            }
        }

        if reasons.isEmpty {
            reasons.append(.generallyBetter)
        }

        return reasons.sorted { priorityOf($0) < priorityOf($1) }
    }

    // MARK: - Private helpers

    private static func boardsMatch(_ a: BoardState, _ b: BoardState) -> Bool {
        a.points == b.points
            && a.whiteBar == b.whiteBar
            && a.blackBar == b.blackBar
            && a.whiteBorneOff == b.whiteBorneOff
            && a.blackBorneOff == b.blackBorneOff
    }

    // How many of the 36 possible dice rolls let black hit at least one white blot
    // from the given board state. Non-doubles count 2, doubles count 1 (sums to 36).
    // Per-zone hit counts: [blackHome(19-24), blackOuter(13-18), whiteOuter(7-12), whiteHome(1-6)]
    // Single pass over 21 rolls — checks all 4 zones at once.
    static func countHittingRollsByZone(against state: BoardState) -> [Int] {
        let zoneRanges: [ClosedRange<Int>] = [19...24, 13...18, 7...12, 1...6]
        var oppBase = state
        oppBase.currentPlayer = .black
        let blotsByZone = zoneRanges.map { r in Set(r.filter { state.points[$0] == 1 }) }
        guard blotsByZone.contains(where: { !$0.isEmpty }) else { return [0, 0, 0, 0] }
        var counts = [0, 0, 0, 0]
        for d1 in 1...6 {
            for d2 in d1...6 {
                let weight = d1 == d2 ? 1 : 2
                let moves = MoveGenerator.legalMoves(for: oppBase, dice: Dice(d1, d2))
                for (i, blots) in blotsByZone.enumerated() where !blots.isEmpty {
                    if moves.contains(where: { move in move.contains { blots.contains($0.to) } }) {
                        counts[i] += weight
                    }
                }
            }
        }
        return counts
    }

    static func countHittingRolls(against state: BoardState) -> Int {
        var oppBase = state
        oppBase.currentPlayer = .black
        let blots = Set((1...24).filter { state.points[$0] == 1 })
        guard !blots.isEmpty else { return 0 }
        var total = 0
        for d1 in 1...6 {
            for d2 in d1...6 {
                let moves = MoveGenerator.legalMoves(for: oppBase, dice: Dice(d1, d2))
                if moves.contains(where: { move in move.contains { blots.contains($0.to) } }) {
                    total += d1 == d2 ? 1 : 2
                }
            }
        }
        return total
    }

    private static func priorityOf(_ reason: ExplanationReason) -> Int {
        switch reason {
        case .missedHit:                  return 0
        case .exposureDifference,
             .unnecessaryBlot:            return 1
        case .badHit:                     return 2
        case .missedPoint:                return 3
        case .racingDecision:             return 4
        case .primeDifference:            return 5
        case .brokenAnchor:               return 6
        case .bearOffSafety:              return 7
        case .overstacking:               return 8
        case .homeBoardWeakened:          return 9
        case .outcomeTradeoff:            return 10
        case .generallyBetter:            return 99
        }
    }
}
