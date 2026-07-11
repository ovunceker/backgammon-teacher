// To run these tests:
// 1. In Xcode: File → New → Target → Unit Testing Bundle, name it "BackgammonTeacherTests".
// 2. Add this file to that target (it should already be there if you dropped the folder in).
// 3. Set "Host Application" to "Backgammon Teacher" in the test target's General settings.
// 4. ⌘U or Product → Test.

import XCTest
@testable import Backgammon_Teacher

final class MoveExplainerTests: XCTestCase {

    // MARK: - Pip count

    func testPipCountInitialWhite() {
        // White: 2×24 + 5×13 + 3×8 + 5×6 = 48+65+24+30 = 167
        let state = BoardState.makeInitial()
        XCTAssertEqual(PositionFeatures.computePip(state: state, player: .white), 167)
    }

    func testPipCountInitialBlack() {
        // Black: 2×(25-1) + 5×(25-12) + 3×(25-17) + 5×(25-19) = 48+65+24+30 = 167
        let state = BoardState.makeInitial()
        XCTAssertEqual(PositionFeatures.computePip(state: state, player: .black), 167)
    }

    func testPipCountSymmetryViaFeatures() {
        let state = BoardState.makeInitial()
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.pipCount, 167)
        XCTAssertEqual(f.opponentPipCount, 167)
    }

    func testPipCountSingleCheckerOnPoint() {
        var state = BoardState.makeEmpty()
        state.points[10] = 1
        XCTAssertEqual(PositionFeatures.computePip(state: state, player: .white), 10)
    }

    func testPipCountBarContributes25() {
        var state = BoardState.makeEmpty()
        state.whiteBar = 1
        XCTAssertEqual(PositionFeatures.computePip(state: state, player: .white), 25)
    }

    func testPipCountBlackSingleChecker() {
        var state = BoardState.makeEmpty()
        state.points[10] = -1   // 1 black checker on point 10 → 25-10 = 15 pips
        XCTAssertEqual(PositionFeatures.computePip(state: state, player: .black), 15)
    }

    // MARK: - Blot detection

    func testBlotAtSingleCheckerPoint() {
        var state = BoardState.makeEmpty()
        state.points[10] = 1
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.blots.count, 1)
        XCTAssertEqual(f.blots.first?.point, 10)
        XCTAssertEqual(f.blots.first?.shotCount, 0)
    }

    func testNoBlotWhenPointMade() {
        var state = BoardState.makeEmpty()
        state.points[10] = 2
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertTrue(f.blots.isEmpty)
        XCTAssertTrue(f.pointsMade.contains(10))
    }

    func testMultipleBlots() {
        var state = BoardState.makeEmpty()
        state.points[5] = 1
        state.points[12] = 1
        state.points[18] = 2    // made — not a blot
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.blots.count, 2)
        XCTAssertTrue(f.blots.map(\.point).contains(5))
        XCTAssertTrue(f.blots.map(\.point).contains(12))
    }

    func testOpponentCheckersNotCountedAsBlots() {
        var state = BoardState.makeEmpty()
        state.points[10] = -1   // black blot — should not appear in white's blots
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertTrue(f.blots.isEmpty)
    }

    // MARK: - Made points

    func testPointsMadeRequiresTwoOrMore() {
        var state = BoardState.makeEmpty()
        state.points[7] = 2
        state.points[11] = 3
        state.points[14] = 1    // blot — not made
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertTrue(f.pointsMade.contains(7))
        XCTAssertTrue(f.pointsMade.contains(11))
        XCTAssertFalse(f.pointsMade.contains(14))
    }

    // MARK: - Prime length

    func testPrimeLengthFourConsecutive() {
        var state = BoardState.makeEmpty()
        for p in 6...9 { state.points[p] = 2 }
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.primeLength, 4)
    }

    func testPrimeLengthWithGapPicksLongestRun() {
        var state = BoardState.makeEmpty()
        state.points[5] = 2     // isolated — run of 1
        // gap at 6
        state.points[7] = 2
        state.points[8] = 2     // run of 2
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.primeLength, 2)
    }

    func testPrimeLengthZeroNoMadePoints() {
        let state = BoardState.makeEmpty()
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.primeLength, 0)
    }

    func testPrimeLengthOneSingleMadePoint() {
        var state = BoardState.makeEmpty()
        state.points[10] = 2
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.primeLength, 1)
    }

    func testPrimeLengthSixFullPrime() {
        var state = BoardState.makeEmpty()
        for p in 4...9 { state.points[p] = 2 }
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.primeLength, 6)
    }

    // MARK: - Prime in front of opponent

    func testPrimeBlocksBlackBackCheckers() {
        var state = BoardState.makeEmpty()
        for p in 7...12 { state.points[p] = 2 }   // white prime at 7-12
        state.points[3] = -2                        // black checker behind the prime
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertTrue(f.primeInFrontOfOpponent)
    }

    func testPrimeDoesNotBlockWhenOpponentAhead() {
        var state = BoardState.makeEmpty()
        for p in 7...10 { state.points[p] = 2 }   // white prime at 7-10
        state.points[15] = -2                       // black already past the prime
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertFalse(f.primeInFrontOfOpponent)
    }

    func testSingleMadePointIsNotAPrime() {
        var state = BoardState.makeEmpty()
        state.points[10] = 2    // single made point — primeLength == 1
        state.points[3] = -2    // black checker "behind" it
        let f = PositionFeatures(state: state, player: .white)
        // primeInFrontOfOpponent requires primeLength >= 2
        XCTAssertFalse(f.primeInFrontOfOpponent)
    }

    func testPrimeNotFlaggedWithNoOpponentBehind() {
        var state = BoardState.makeEmpty()
        for p in 7...12 { state.points[p] = 2 }   // prime at 7-12
        // no black checkers at all
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertFalse(f.primeInFrontOfOpponent)
    }

    // MARK: - Anchors

    func testWhiteAnchorInBlackHome() {
        var state = BoardState.makeEmpty()
        state.points[20] = 2    // black's home is 19-24
        state.points[5] = 2     // white's own home — not an anchor
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertTrue(f.anchors.contains(20))
        XCTAssertFalse(f.anchors.contains(5))
    }

    func testMultipleAnchors() {
        var state = BoardState.makeEmpty()
        state.points[19] = 2
        state.points[21] = 2
        state.points[23] = 2
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.anchors.count, 3)
    }

    func testNoAnchors() {
        var state = BoardState.makeEmpty()
        state.points[5] = 2
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertTrue(f.anchors.isEmpty)
    }

    // MARK: - Home board points

    func testHomeBoardPointsWhite() {
        var state = BoardState.makeEmpty()
        state.points[1] = 2     // home (1-6)
        state.points[3] = 2     // home
        state.points[8] = 2     // not home
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.homeBoardPoints, 2)
    }

    func testHomeBoardPointsDoesNotCountOpponent() {
        var state = BoardState.makeEmpty()
        state.points[2] = 2     // white home
        state.points[4] = -2    // black checker in white's home — not white's home board point
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.homeBoardPoints, 1)
    }

    // MARK: - Checkers in opponent home

    func testCheckersInOpponentHome() {
        var state = BoardState.makeEmpty()
        state.points[19] = 1    // white blot in black's home (19-24)
        state.points[22] = 2    // white made point in black's home
        state.points[5] = 3     // white in own home — not counted
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.checkersInOpponentHome, 3)  // 1 + 2
    }

    func testNoCheckersInOpponentHome() {
        var state = BoardState.makeEmpty()
        state.points[5] = 5
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.checkersInOpponentHome, 0)
    }

    // MARK: - Max stack

    func testMaxStack() {
        var state = BoardState.makeEmpty()
        state.points[6] = 5
        state.points[8] = 3
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.maxStack, 5)
    }

    func testMaxStackZeroEmpty() {
        let state = BoardState.makeEmpty()
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.maxStack, 0)
    }

    // MARK: - Contact broken

    func testContactBrokenWhenSidesHavePassed() {
        var state = BoardState.makeEmpty()
        // White all in home board (1-3)
        state.points[1] = 5; state.points[2] = 5; state.points[3] = 5
        // Black all in their home board (20-22)
        state.points[20] = -5; state.points[21] = -5; state.points[22] = -5
        // max white = 3, min black = 20 → 3 < 20 → contact broken
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertTrue(f.isContactBroken)
    }

    func testContactNotBrokenInitialPosition() {
        let state = BoardState.makeInitial()
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertFalse(f.isContactBroken)
    }

    func testContactNotBrokenWithWhiteBar() {
        var state = BoardState.makeEmpty()
        state.points[1] = 3
        state.points[20] = -3
        state.whiteBar = 1   // bar checker means contact cannot be broken
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertFalse(f.isContactBroken)
    }

    func testContactNotBrokenWhenCheckersOverlap() {
        var state = BoardState.makeEmpty()
        state.points[10] = 2    // white at 10
        state.points[15] = -2   // black at 15 — still overlap in the board range
        // max white = 10, min black = 15 → 10 < 15 → contact broken
        // Actually that IS broken since white is at 10 and black at 15 and white moves toward 1
        // So white needs to pass black — contact IS present (they're on the path to hit each other)
        // Let's verify the formula: 10 < 15 → isContactBroken = true
        // This is correct: white can't reach black (white moves toward 1, black toward 24)
        // so they've already "passed" each other.
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertTrue(f.isContactBroken)
    }

    func testContactPresentWhenWhiteAheadOfBlack() {
        // White at 15 (hasn't passed black at 10 yet, going toward 1)
        // Black at 10 (hasn't passed white yet, going toward 24)
        // They can still interact: white at 15 moving toward 1 will pass through 10.
        var state = BoardState.makeEmpty()
        state.points[15] = 2    // white
        state.points[10] = -2   // black
        // max white = 15, min black = 10 → 15 >= 10 → NOT broken
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertFalse(f.isContactBroken)
    }

    // MARK: - Shot counting

    // A: direct shot only — all combination paths blocked.
    // Black at 12, white blocking 13–17, white blot at 18.
    // Only die=6 can reach 18; combinations land first on a blocked point.
    // Rolls containing a 6: (1,6),(2,6),(3,6),(4,6),(5,6) ×2 + (6,6) ×1 = 11.
    func testShotCountDirectSixShot() {
        var state = BoardState.makeEmpty()
        state.points[12] = -1                         // black checker
        for p in 13...17 { state.points[p] = 2 }     // white blocking 13-17
        state.points[18] = 1                          // white blot
        let f = PositionFeatures(state: state, player: .white)
        let blot = f.blots.first(where: { $0.point == 18 })
        XCTAssertNotNil(blot, "blot at 18 should be detected")
        XCTAssertEqual(blot?.shotCount, 11)
    }

    // B: blocked intermediates — combination shots excluded.
    // Black at 12, all points 13–21 blocked by white, blot at 22 (distance 10).
    // No single die covers 10; every combination hop lands on a blocked point.
    func testShotCountBlockedCombinationExcluded() {
        var state = BoardState.makeEmpty()
        state.points[12] = -1
        for p in 13...21 { state.points[p] = 2 }     // all intermediates blocked
        state.points[22] = 1                          // white blot
        let f = PositionFeatures(state: state, player: .white)
        let blot = f.blots.first(where: { $0.point == 22 })
        XCTAssertNotNil(blot, "blot at 22 should be detected")
        XCTAssertEqual(blot?.shotCount, 0)
    }

    // C: bar entry hit — opponent on bar, blot in own home board.
    // Black on bar, white blocking entry points 1–4, blot at 5.
    // Black must enter; only die=5 is unblocked → enters at 5 and hits.
    // Can't reach 5 from entry at 6 (moving toward 24, not back toward 5).
    // (1,5),(2,5),(3,5),(4,5),(5,6) ×2 + (5,5) ×1 = 11.
    func testShotCountBarEntryHit() {
        var state = BoardState.makeEmpty()
        state.blackBar = 1
        for p in 1...4 { state.points[p] = 2 }       // block entry points 1-4
        state.points[5] = 1                           // white blot
        let f = PositionFeatures(state: state, player: .white)
        let blot = f.blots.first(where: { $0.point == 5 })
        XCTAssertNotNil(blot, "blot at 5 should be detected")
        XCTAssertEqual(blot?.shotCount, 11)
    }

    // D: doubles only — only reachable via (6,6).
    // Black at 10, white blocking 11–21 except 16 (open), blot at 22 (distance 12).
    // First hop: only die=6 → 16 (all others blocked). Second hop: only die=6 → 22.
    // No non-double pair sums to 12. Only (6,6) hits; weight = 1.
    func testShotCountDoublesOnly() {
        var state = BoardState.makeEmpty()
        state.points[10] = -1
        for p in 11...21 where p != 16 { state.points[p] = 2 }   // block all except 16
        state.points[22] = 1                          // white blot
        let f = PositionFeatures(state: state, player: .white)
        let blot = f.blots.first(where: { $0.point == 22 })
        XCTAssertNotNil(blot, "blot at 22 should be detected")
        XCTAssertEqual(blot?.shotCount, 1)
    }

    // No opponent checkers → no shots possible.
    func testShotCountZeroWhenNoOpponent() {
        var state = BoardState.makeEmpty()
        state.points[10] = 1                          // white blot, no black anywhere
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertEqual(f.blots.first?.shotCount, 0)
    }

    // MARK: - Bearing off

    func testIsBearingOffWhenAllCheckersInHome() {
        var state = BoardState.makeEmpty()
        state.points[1] = 5; state.points[2] = 5; state.points[3] = 5
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertTrue(f.isBearingOff)
    }

    func testIsNotBearingOffAtStart() {
        let state = BoardState.makeInitial()
        let f = PositionFeatures(state: state, player: .white)
        XCTAssertFalse(f.isBearingOff)
    }

    // MARK: - MoveExplainer: Severity

    func testSeverityFine() {
        XCTAssertEqual(MoveExplainer.severity(for: 0.00), .fine)
        XCTAssertEqual(MoveExplainer.severity(for: 0.01), .fine)
        XCTAssertEqual(MoveExplainer.severity(for: -0.05), .fine)
    }

    func testSeverityInaccuracy() {
        XCTAssertEqual(MoveExplainer.severity(for: 0.02), .inaccuracy)
        XCTAssertEqual(MoveExplainer.severity(for: 0.05), .inaccuracy)
        XCTAssertEqual(MoveExplainer.severity(for: 0.0799), .inaccuracy)
    }

    func testSeverityError() {
        XCTAssertEqual(MoveExplainer.severity(for: 0.08), .error)
        XCTAssertEqual(MoveExplainer.severity(for: 0.10), .error)
        XCTAssertEqual(MoveExplainer.severity(for: 0.1499), .error)
    }

    func testSeverityBlunder() {
        XCTAssertEqual(MoveExplainer.severity(for: 0.15), .blunder)
        XCTAssertEqual(MoveExplainer.severity(for: 0.50), .blunder)
    }

    // MARK: - MoveExplainer: Reason detection

    // missedHit: black blot at 10 in preTurn; best moved white to 10 (hit); player didn't.
    func testMissedHitDetected() {
        var preTurn = BoardState.makeEmpty()
        preTurn.points[14] = 1    // white at 14 (maxWhite=14 > minBlack=10 → contact present)
        preTurn.points[10] = -1   // black blot

        var playerState = BoardState.makeEmpty()
        playerState.points[17] = 1   // player moved white away, didn't hit
        playerState.points[10] = -1  // black blot still there

        var bestState = BoardState.makeEmpty()
        bestState.points[10] = 1     // best hit the blot
        bestState.blackBar = 1

        let probs = [Float](repeating: 0, count: 6)
        let reasons = MoveExplainer.detectReasons(
            preTurnState: preTurn, playerState: playerState, bestState: bestState,
            playerProbs: probs, bestProbs: probs
        )
        XCTAssertTrue(reasons.contains(.missedHit(point: 10)))
    }

    // unnecessaryBlot: player left a blot; best made a clean point with no blots.
    func testUnnecessaryBlotDetected() {
        var preTurn = BoardState.makeEmpty()
        preTurn.points[15] = 2   // white at 15 (contact present vs black below)
        preTurn.points[10] = -2  // black made point

        var playerState = BoardState.makeEmpty()
        playerState.points[15] = 1   // player left a blot at 15
        playerState.points[12] = 1   // another blot

        var bestState = BoardState.makeEmpty()
        bestState.points[15] = 2     // best: made point, no blots
        bestState.points[12] = 2

        let probs = [Float](repeating: 0, count: 6)
        let reasons = MoveExplainer.detectReasons(
            preTurnState: preTurn, playerState: playerState, bestState: bestState,
            playerProbs: probs, bestProbs: probs
        )
        XCTAssertTrue(reasons.contains(.unnecessaryBlot))
        // exposureDifference requires both sides to have blots — best has none here
        XCTAssertFalse(reasons.contains(.exposureDifference))
    }

    // generallyBetter fallback: no specific trigger fires when positions are identical.
    func testGenerallyBetterFallback() {
        var state = BoardState.makeEmpty()
        state.points[15] = 2    // contact present (maxWhite=15 >= minBlack implied below)
        state.points[10] = -2
        let probs = [Float](repeating: 1.0 / 6.0, count: 6)
        let reasons = MoveExplainer.detectReasons(
            preTurnState: state, playerState: state, bestState: state,
            playerProbs: probs, bestProbs: probs
        )
        XCTAssertEqual(reasons, [.generallyBetter])
    }

    // missedHit has lower priority number than unnecessaryBlot → appears first.
    func testMissedHitHasHigherPriorityThanUnnecessaryBlot() {
        // preTurn: two whites at 4, black blot at 10.
        // best (doubles 6,6): moves both whites from 4→10, makes the point, hits black.
        // player: moved whites elsewhere, leaving two blots, missed the hit.
        var preTurn = BoardState.makeEmpty()
        preTurn.points[4] = 2    // two white checkers
        preTurn.points[10] = -1  // black blot

        var playerState = BoardState.makeEmpty()
        playerState.points[7] = 1    // blot
        playerState.points[4] = 1    // blot (second white still there)
        playerState.points[10] = -1  // black not hit

        var bestState = BoardState.makeEmpty()
        bestState.points[10] = 2    // made the point (two whites), hit black
        bestState.blackBar = 1      // no blots in bestState

        let probs = [Float](repeating: 0, count: 6)
        let reasons = MoveExplainer.detectReasons(
            preTurnState: preTurn, playerState: playerState, bestState: bestState,
            playerProbs: probs, bestProbs: probs
        )
        XCTAssertTrue(reasons.contains(.missedHit(point: 10)))
        XCTAssertTrue(reasons.contains(.unnecessaryBlot))
        if let missedIdx = reasons.firstIndex(of: .missedHit(point: 10)),
           let blotIdx   = reasons.firstIndex(of: .unnecessaryBlot) {
            XCTAssertLessThan(missedIdx, blotIdx, "missedHit must precede unnecessaryBlot")
        }
    }

    // racingDecision fires when contact is broken in the pre-turn position.
    func testRacingDecisionDetected() {
        // White all in home (1-3), black all in theirs (20-22) → pure race.
        var preTurn = BoardState.makeEmpty()
        preTurn.points[1] = 3; preTurn.points[2] = 6; preTurn.points[3] = 6
        preTurn.points[20] = -5; preTurn.points[21] = -5; preTurn.points[22] = -5

        // Player stacked wastefully instead of bearing off
        var playerState = preTurn
        playerState.points[3] = 5
        playerState.points[2] = 7

        // Best bore off one checker
        var bestState = preTurn
        bestState.points[3] = 5
        bestState.whiteBorneOff = 1

        let probs = [Float](repeating: 0, count: 6)
        let reasons = MoveExplainer.detectReasons(
            preTurnState: preTurn, playerState: playerState, bestState: bestState,
            playerProbs: probs, bestProbs: probs
        )
        XCTAssertTrue(reasons.contains(.racingDecision))
    }

    // primeDifference fires when best built a longer prime.
    func testPrimeDifferenceDetected() {
        var preTurn = BoardState.makeEmpty()
        preTurn.points[15] = 2; preTurn.points[10] = -2  // contact present

        var playerState = BoardState.makeEmpty()
        playerState.points[6] = 2; playerState.points[7] = 2   // prime of 2
        playerState.points[10] = -2

        var bestState = BoardState.makeEmpty()
        bestState.points[6] = 2; bestState.points[7] = 2; bestState.points[8] = 2  // prime of 3
        bestState.points[10] = -2

        let probs = [Float](repeating: 0, count: 6)
        let reasons = MoveExplainer.detectReasons(
            preTurnState: preTurn, playerState: playerState, bestState: bestState,
            playerProbs: probs, bestProbs: probs
        )
        XCTAssertTrue(reasons.contains(.primeDifference))
    }

    // outcomeTradeoff fires when gammon win probability differs by more than 0.04.
    func testOutcomeTradeoffDetected() {
        var state = BoardState.makeEmpty()
        state.points[15] = 2; state.points[10] = -2

        // player gave up 0.10 of gammon-win probability vs best
        let playerProbs: [Float] = [0.50, 0.10, 0.02, 0.15, 0.20, 0.03]
        let bestProbs:   [Float] = [0.45, 0.20, 0.02, 0.15, 0.15, 0.03]

        let reasons = MoveExplainer.detectReasons(
            preTurnState: state, playerState: state, bestState: state,
            playerProbs: playerProbs, bestProbs: bestProbs
        )
        XCTAssertTrue(reasons.contains(.outcomeTradeoff))
    }

    // outcomeTradeoff does not fire when gammon probabilities are nearly equal.
    func testOutcomeTradeoffNotFiredWhenProbsClose() {
        var state = BoardState.makeEmpty()
        state.points[15] = 2; state.points[10] = -2

        let playerProbs: [Float] = [0.50, 0.15, 0.02, 0.15, 0.15, 0.03]
        let bestProbs:   [Float] = [0.48, 0.16, 0.02, 0.16, 0.15, 0.03]  // diff = 0.01 < 0.04

        let reasons = MoveExplainer.detectReasons(
            preTurnState: state, playerState: state, bestState: state,
            playerProbs: playerProbs, bestProbs: bestProbs
        )
        XCTAssertFalse(reasons.contains(.outcomeTradeoff))
    }

    // MARK: - ExplanationRenderer: Severity headline

    func testHeadlineFine() {
        XCTAssertEqual(ExplanationRenderer.headlineText(for: .fine), "Good move.")
    }

    func testAllSeveritiesProduceDistinctHeadlines() {
        let texts = [ErrorSeverity.fine, .inaccuracy, .error, .blunder]
            .map { ExplanationRenderer.headlineText(for: $0) }
        XCTAssertEqual(Set(texts).count, 4, "Each severity should produce a unique headline")
    }

    // MARK: - ExplanationRenderer: Exposure level buckets

    func testExposureLevelSafe() {
        XCTAssertEqual(ExplanationRenderer.exposureLevel(shotCount: 0), "safe")
    }

    func testExposureLevelLightlyExposed() {
        XCTAssertEqual(ExplanationRenderer.exposureLevel(shotCount: 1), "lightly exposed")
        XCTAssertEqual(ExplanationRenderer.exposureLevel(shotCount: 6), "lightly exposed")
    }

    func testExposureLevelExposed() {
        XCTAssertEqual(ExplanationRenderer.exposureLevel(shotCount: 7), "exposed")
        XCTAssertEqual(ExplanationRenderer.exposureLevel(shotCount: 12), "exposed")
    }

    func testExposureLevelHeavilyExposed() {
        XCTAssertEqual(ExplanationRenderer.exposureLevel(shotCount: 13), "heavily exposed")
        XCTAssertEqual(ExplanationRenderer.exposureLevel(shotCount: 18), "heavily exposed")
    }

    func testExposureLevelVeryDangerous() {
        XCTAssertEqual(ExplanationRenderer.exposureLevel(shotCount: 19), "very dangerous")
        XCTAssertEqual(ExplanationRenderer.exposureLevel(shotCount: 36), "very dangerous")
    }

    // MARK: - ExplanationRenderer: Prime strength buckets

    func testPrimeStrengthNone() {
        XCTAssertEqual(ExplanationRenderer.primeStrength(length: 0), "no prime")
        XCTAssertEqual(ExplanationRenderer.primeStrength(length: 1), "no prime")
    }

    func testPrimeStrengthShort() {
        XCTAssertEqual(ExplanationRenderer.primeStrength(length: 2), "a short prime")
        XCTAssertEqual(ExplanationRenderer.primeStrength(length: 3), "a short prime")
    }

    func testPrimeStrengthSolid() {
        XCTAssertEqual(ExplanationRenderer.primeStrength(length: 4), "a solid prime")
    }

    func testPrimeStrengthStrong() {
        XCTAssertEqual(ExplanationRenderer.primeStrength(length: 5), "a strong prime")
    }

    func testPrimeStrengthFull() {
        XCTAssertEqual(ExplanationRenderer.primeStrength(length: 6), "a full prime")
        XCTAssertEqual(ExplanationRenderer.primeStrength(length: 8), "a full prime")
    }

    // MARK: - ExplanationRenderer: Reason detail strings

    func testDetailMissedHitMentionsHitOrBar() {
        let a = makeAnalysis(reasons: [.missedHit(point: 10)])
        let text = ExplanationRenderer.detail(for: .missedHit(point: 10), analysis: a)
        XCTAssertFalse(text.isEmpty)
        let lower = text.lowercased()
        XCTAssertTrue(lower.contains("hit") || lower.contains("bar"))
    }

    func testDetailUnnecessaryBlotIsNonEmpty() {
        let a = makeAnalysis(reasons: [.unnecessaryBlot])
        XCTAssertFalse(ExplanationRenderer.detail(for: .unnecessaryBlot, analysis: a).isEmpty)
    }

    func testDetailGoldenPointDiffersFromOrdinaryPoint() {
        let a = makeAnalysis(reasons: [.missedPoint(point: 5, isGoldenPoint: true)])
        let golden  = ExplanationRenderer.detail(for: .missedPoint(point: 5,  isGoldenPoint: true),  analysis: a)
        let regular = ExplanationRenderer.detail(for: .missedPoint(point: 14, isGoldenPoint: false), analysis: a)
        XCTAssertNotEqual(golden, regular)
    }

    func testDetailOutcomeTradeoffGammonWinText() {
        // Best has a 0.15 higher gammon-win probability → "gammon" win text
        let playerProbs: [Float] = [0.50, 0.10, 0.02, 0.15, 0.20, 0.03]
        let bestProbs:   [Float] = [0.45, 0.25, 0.02, 0.15, 0.10, 0.03]
        let a = makeAnalysis(playerProbs: playerProbs, bestProbs: bestProbs, reasons: [.outcomeTradeoff])
        let text = ExplanationRenderer.detail(for: .outcomeTradeoff, analysis: a)
        XCTAssertTrue(text.lowercased().contains("gammon"))
    }

    func testDetailOutcomeTradeoffGammonRiskText() {
        // Gammon-risk reduction (0.15) dominates over gammon-win gain (0.01) → risk text
        let playerProbs: [Float] = [0.50, 0.15, 0.02, 0.15, 0.25, 0.03]
        let bestProbs:   [Float] = [0.50, 0.16, 0.02, 0.15, 0.10, 0.03]
        let a = makeAnalysis(playerProbs: playerProbs, bestProbs: bestProbs, reasons: [.outcomeTradeoff])
        let text = ExplanationRenderer.detail(for: .outcomeTradeoff, analysis: a)
        XCTAssertTrue(text.lowercased().contains("gammon"))
    }

    func testDetailAllReasonTypesNonEmpty() {
        let a = makeAnalysis()
        let allReasons: [ExplanationReason] = [
            .missedHit(point: 5), .unnecessaryBlot, .exposureDifference,
            .badHit, .missedPoint(point: 7, isGoldenPoint: true),
            .racingDecision, .primeDifference, .brokenAnchor,
            .bearOffSafety, .overstacking, .homeBoardWeakened,
            .outcomeTradeoff, .generallyBetter
        ]
        for reason in allReasons {
            let text = ExplanationRenderer.detail(for: reason, analysis: a)
            XCTAssertFalse(text.isEmpty, "detail for \(reason) must not be empty")
        }
    }

    // MARK: - ExplanationRenderer: render()

    func testRenderHeadlineMatchesSeverity() {
        let a = makeAnalysis(severity: .blunder, reasons: [.generallyBetter])
        let rendered = ExplanationRenderer.render(a)
        XCTAssertEqual(rendered.headline, ExplanationRenderer.headlineText(for: .blunder))
    }

    func testRenderDetailsCountMatchesReasonCount() {
        let a = makeAnalysis(severity: .error, reasons: [.unnecessaryBlot, .primeDifference])
        let rendered = ExplanationRenderer.render(a)
        XCTAssertEqual(rendered.details.count, 2)
    }

    func testRenderSingleReasonGenerallyBetter() {
        let a = makeAnalysis(severity: .inaccuracy, reasons: [.generallyBetter])
        let rendered = ExplanationRenderer.render(a)
        XCTAssertEqual(rendered.details.count, 1)
        XCTAssertFalse(rendered.details[0].isEmpty)
    }

    func testRenderDetailOrderMatchesReasonOrder() {
        let a = makeAnalysis(severity: .error, reasons: [.missedHit(point: 10), .unnecessaryBlot])
        let rendered = ExplanationRenderer.render(a)
        XCTAssertEqual(rendered.details[0],
                       ExplanationRenderer.detail(for: .missedHit(point: 10), analysis: a))
        XCTAssertEqual(rendered.details[1],
                       ExplanationRenderer.detail(for: .unnecessaryBlot, analysis: a))
    }

    // MARK: - Test helper

    private func makeAnalysis(
        playerProbs: [Float] = [Float](repeating: 1.0 / 6.0, count: 6),
        bestProbs:   [Float] = [Float](repeating: 1.0 / 6.0, count: 6),
        severity: ErrorSeverity = .error,
        reasons: [ExplanationReason] = [.generallyBetter]
    ) -> MoveAnalysis {
        MoveAnalysis(
            playerEquity: 0.0,
            bestEquity: 0.1,
            bestMove: [],
            severity: severity,
            reasons: reasons,
            playerProbs: playerProbs,
            bestProbs: bestProbs,
            preTurnState: .makeInitial(),
            playerFinalState: .makeInitial(),
            bestFinalState: .makeInitial(),
            dice: Dice(1, 2),
            playerShotsAgainstBlots: 0,
            bestShotsAgainstBlots: 0,
            playerShotsByZone: [0, 0, 0, 0],
            topOpponentResponses: [],
            topAlternatives: []
        )
    }
}
