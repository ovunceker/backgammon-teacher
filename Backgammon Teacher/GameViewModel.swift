import SwiftUI

@Observable
final class GameViewModel {
    var state: BoardState = .makeInitial()
    var dice: Dice? = nil
    var selectedPoint: Int? = nil
    private(set) var allLegalMoves: [Move] = []
    private var history: [(BoardState, Dice)] = []

    var canRoll: Bool { dice == nil && state.winner == nil }
    var canUndo: Bool { !history.isEmpty }
    var pendingEndTurn: Bool = false

    // All points the selected checker can reach — single die, either die, or both dice on
    // the same checker (e.g. rolling 2+5 shows destinations 2 steps, 5 steps, and 7 steps away).
    var legalDestinations: Set<Int> {
        guard let src = selectedPoint, let d = dice else { return [] }
        let player = state.currentPlayer
        var dests = Set<Int>()

        // Pass 1 — trace every position this checker visits or ends at across all legal moves.
        // This naturally surfaces combined destinations (2+5 = 7 steps) from the move tree.
        for move in allLegalMoves {
            var pos = src
            for step in move {
                if step.from == pos {
                    pos = step.to
                    dests.insert(pos)
                }
            }
        }

        // Pass 2 — add direct single-die board destinations.
        // Deduplication in MoveGenerator keeps only one ordering of equivalent moves, so some
        // first-step die choices disappear from Pass 1. Adding them here restores them.
        for die in Set(d.remaining) {
            let dest = src + player.direction * die
            if (1...24).contains(dest), !state.isBlocked(at: dest, for: player) {
                dests.insert(dest)
            }
        }

        return dests
    }

    // Every checker position that appears as the *initial* from-point in any legal move step.
    var selectableSources: Set<Int> {
        var sources = Set<Int>()
        for move in allLegalMoves {
            var created = Set<Int>()          // positions born mid-move (not selectable)
            for step in move {
                if !created.contains(step.from) { sources.insert(step.from) }
                created.insert(step.to)
            }
        }
        return sources
    }

    func rollDice() {
        guard canRoll else { return }
        let d = Dice()
        dice = d
        allLegalMoves = MoveGenerator.legalMoves(for: state, dice: d)
        if allLegalMoves.isEmpty {
            pendingEndTurn = true
            return
        }
        if state.barCount(for: state.currentPlayer) > 0 {
            selectedPoint = state.currentPlayer.barPoint
        }
    }

    func tap(point: Int) {
        if selectedPoint != nil, legalDestinations.contains(point) {
            commitMove(to: point); return
        }
        if selectableSources.contains(point) {
            selectedPoint = (selectedPoint == point) ? nil : point
        }
    }

    func tapBoreOff() {
        let dest = state.currentPlayer.boreOffPoint
        if legalDestinations.contains(dest) { commitMove(to: dest) }
    }

    func undoStep() {
        guard let (prevState, prevDice) = history.popLast() else { return }
        state = prevState
        dice = prevDice
        selectedPoint = nil
        pendingEndTurn = false
        allLegalMoves = MoveGenerator.legalMoves(for: state, dice: prevDice)
    }

    private func commitMove(to dest: Int) {
        guard let src = selectedPoint, let snap = dice else { return }
        history.append((state, snap))
        let player = state.currentPlayer

        // Case 1: dest is the first step of a legal complete move — standard path.
        if let move = allLegalMoves.first(where: { $0.first?.from == src && $0.first?.to == dest }),
           let step = move.first {
            applyStep(step)

        // Case 2: dest is reached mid-move on this checker (e.g. the 2+5=7 combined destination).
        //         Walk the move sequence, applying only the steps that advance the selected checker.
        } else if let move = allLegalMoves.first(where: { m in
            var pos = src
            for s in m { if s.from == pos { pos = s.to; if pos == dest { return true } } }
            return false
        }) {
            var pos = src
            for s in move {
                if s.from == pos { applyStep(s); pos = s.to; if pos == dest { break } }
            }

        // Case 3: direct single-die move that was removed from allLegalMoves by deduplication.
        //         Reconstruct it from the die value implied by the distance.
        } else {
            let dist = (src - dest) * player.direction
            guard let d = dice, d.remaining.contains(dist) else { return }
            applyStep(CheckerMove(from: src, to: dest, die: dist))
        }

        selectedPoint = nil
        finishTurn()
    }

    private func applyStep(_ step: CheckerMove) {
        state = state.applying(step)
        dice?.markUsed(die: step.die)
    }

    func newGame() {
        state = .makeInitial()
        dice = nil; selectedPoint = nil; allLegalMoves = []; history = []; pendingEndTurn = false
    }

    func confirmEndTurn() { endTurn() }

    private func finishTurn() {
        guard let d = dice, !d.isDone else { pendingEndTurn = true; return }
        allLegalMoves = MoveGenerator.legalMoves(for: state, dice: d)
        if allLegalMoves.isEmpty { pendingEndTurn = true; return }
        if state.barCount(for: state.currentPlayer) > 0 {
            selectedPoint = state.currentPlayer.barPoint
        }
    }

    private func endTurn() {
        pendingEndTurn = false
        dice = nil; allLegalMoves = []; selectedPoint = nil; history = []
        state.currentPlayer = state.currentPlayer.opponent
    }
}
