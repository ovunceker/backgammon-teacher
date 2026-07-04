import Foundation

// MARK: - RenderedExplanation

struct RenderedExplanation {
    let headline: String
    let details: [String]   // one entry per reason, in priority order
}

// MARK: - ExplanationRenderer

struct ExplanationRenderer {

    // MARK: - Public API

    static func render(_ analysis: MoveAnalysis) -> RenderedExplanation {
        RenderedExplanation(
            headline: headlineText(for: analysis.severity),
            details: analysis.reasons.map { detail(for: $0, analysis: analysis) }
        )
    }

    // MARK: - Severity headline (internal for testing)

    static func headlineText(for severity: ErrorSeverity) -> String {
        switch severity {
        case .fine:       return "Good move."
        case .inaccuracy: return "There was a slightly better option."
        case .error:      return "That move gave up some ground."
        case .blunder:    return "That was a costly mistake."
        }
    }

    // MARK: - Reason detail (internal for testing)

    static func detail(for reason: ExplanationReason, analysis: MoveAnalysis) -> String {
        switch reason {
        case .missedHit:
            return "You could have hit an opponent's blot and sent it to the bar."
        case .unnecessaryBlot:
            return "You left a checker exposed when you didn't need to."
        case .exposureDifference:
            return "Your checker is left in a much more dangerous position than necessary."
        case .badHit:
            return "Hitting there left your own checker too vulnerable in return."
        case .missedPoint(_, let isGolden):
            return isGolden
                ? "You missed a chance to make a key point that would have been very difficult for your opponent."
                : "You missed a chance to make a strong point."
        case .racingDecision:
            return "In a pure race, every pip counts — the better move is more efficient."
        case .primeDifference:
            return "The better move builds a stronger blocking wall."
        case .brokenAnchor:
            return "Giving up your anchor leaves you with fewer defensive options."
        case .bearOffSafety:
            return "In the bear-off, it's better to avoid leaving any checker exposed."
        case .overstacking:
            return "Spreading your checkers more evenly gives you better flexibility."
        case .homeBoardWeakened:
            return "The better move keeps your home board stronger."
        case .outcomeTradeoff:
            return outcomeTradeoffDetail(analysis: analysis)
        case .generallyBetter:
            return "The computer found a move with better overall prospects."
        }
    }

    // MARK: - Qualitative buckets (internal for testing)

    /// Maps a blot's shot count (out of 36) to a qualitative exposure label.
    static func exposureLevel(shotCount: Int) -> String {
        switch shotCount {
        case 0:        return "safe"
        case 1...6:    return "lightly exposed"
        case 7...12:   return "exposed"
        case 13...18:  return "heavily exposed"
        default:       return "very dangerous"
        }
    }

    /// Maps the length of a consecutive prime to a qualitative label.
    static func primeStrength(length: Int) -> String {
        switch length {
        case 0, 1: return "no prime"
        case 2, 3: return "a short prime"
        case 4:    return "a solid prime"
        case 5:    return "a strong prime"
        default:   return "a full prime"
        }
    }

    // MARK: - Private helpers

    private static func outcomeTradeoffDetail(analysis: MoveAnalysis) -> String {
        guard analysis.playerProbs.count == 6, analysis.bestProbs.count == 6 else {
            return "The better move has a more favourable outcome profile."
        }
        let gammonWinDiff  = analysis.bestProbs[1] - analysis.playerProbs[1]
        let gammonRiskDiff = analysis.playerProbs[4] - analysis.bestProbs[4]
        return gammonWinDiff > gammonRiskDiff
            ? "The better move gives you a better chance of winning a gammon."
            : "The better move reduces your risk of losing a gammon."
    }
}
