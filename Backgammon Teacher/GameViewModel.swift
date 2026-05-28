import SwiftUI

struct FlightInfo: Equatable {
    let id: UUID
    let from: Int
    let to: Int
    let isWhite: Bool
    let isAutoPlay: Bool

    init(from: Int, to: Int, isWhite: Bool, isAutoPlay: Bool = false) {
        self.id = UUID()
        self.from = from; self.to = to; self.isWhite = isWhite; self.isAutoPlay = isAutoPlay
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

@Observable
final class GameViewModel {
    var state: BoardState = .makeInitial()
    var dice: Dice? = nil
    var selectedPoint: Int? = nil
    private(set) var allLegalMoves: [Move] = []
    private var history: [(BoardState, Dice)] = []
    var flightInfo: FlightInfo? = nil
    private(set) var diceRollID: Int = 0
    var dragSource: Int? = nil
    var dragPosition: CGPoint? = nil
    private(set) var whiteScore: Int = 0
    private(set) var blackScore: Int = 0
    private var scoreRecorded: Bool = false
    private(set) var noMovesAvailable: Bool = false
    private(set) var resignedWinner: Player? = nil
    private var autoEndTask: Task<Void, Never>?
    private var autoPlayTask: Task<Void, Never>?
    private var isAutoPlayInProgress: Bool = false

    var effectiveWinner: Player? { resignedWinner ?? state.winner }
    var canRoll: Bool { dice == nil && state.winner == nil && resignedWinner == nil && !isSetupMode }
    var canUndo: Bool { !history.isEmpty }
    var pendingEndTurn: Bool = false

    var isSetupMode: Bool = false
    var setupColor: Player = .white

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
        diceRollID += 1
        allLegalMoves = MoveGenerator.legalMoves(for: state, dice: d)
        if allLegalMoves.isEmpty {
            noMovesAvailable = true
            scheduleAutoEnd()
            return
        }
        if state.barCount(for: state.currentPlayer) > 0 {
            selectedPoint = state.currentPlayer.barPoint
        }
        scheduleAutoPlay(delay: 1500)
    }

    func tap(point: Int) {
        if isSetupMode { tapSetup(point: point); return }
        guard let d = dice else { return }
        let player = state.currentPlayer

        // Hard bar enforcement: if the current player has checkers on the bar,
        // only the bar point itself or a highlighted entry destination may be tapped.
        if state.barCount(for: player) > 0 {
            let isBarPoint  = (point == player.barPoint)
            let isEntryDest = (selectedPoint == player.barPoint && legalDestinations.contains(point))
            guard isBarPoint || isEntryDest else { return }
        }

        // Two-tap path: a source is already selected and the user taps a legal destination.
        // This lets bar checkers be placed by tapping the highlighted entry point directly.
        if selectedPoint != nil, legalDestinations.contains(point) {
            commitMove(to: point); return
        }

        guard selectableSources.contains(point) else { return }
        selectedPoint = point   // needed so legalDestinations computes for this checker
        for die in Set(d.remaining).sorted(by: >) {
            let rawDest = point + player.direction * die
            if legalDestinations.contains(rawDest) {
                commitMove(to: rawDest); return
            }
            // Die overshoots the board — bear off if legal
            if !(1...24).contains(rawDest), legalDestinations.contains(player.boreOffPoint) {
                commitMove(to: player.boreOffPoint); return
            }
        }
        selectedPoint = nil   // no single-die move available for this checker
    }

    func undoStep() {
        autoEndTask?.cancel()
        autoPlayTask?.cancel()
        noMovesAvailable = false
        flightInfo = nil; dragSource = nil; dragPosition = nil
        guard let (prevState, prevDice) = history.popLast() else { return }
        state = prevState
        dice = prevDice
        selectedPoint = nil
        pendingEndTurn = false
        allLegalMoves = MoveGenerator.legalMoves(for: state, dice: prevDice)
        if state.barCount(for: state.currentPlayer) > 0 {
            selectedPoint = state.currentPlayer.barPoint
        }
    }

    private func commitMove(to dest: Int) {
        autoPlayTask?.cancel()
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
        // Skip flight animation for drag moves — the user already positioned the checker manually.
        if dragPosition == nil {
            flightInfo = FlightInfo(from: step.from, to: step.to, isWhite: state.currentPlayer == .white, isAutoPlay: isAutoPlayInProgress)
        }
        state = state.applying(step)
        dice?.markUsed(die: step.die)
    }

    // Called by the view after a drag gesture ends on a valid destination point.
    func drop(to dest: Int) {
        defer { dragSource = nil; dragPosition = nil }
        guard legalDestinations.contains(dest) else { selectedPoint = nil; return }
        commitMove(to: dest)
    }

    func cancelDrag() {
        dragSource = nil; dragPosition = nil
        if dice != nil, state.barCount(for: state.currentPlayer) > 0 {
            selectedPoint = state.currentPlayer.barPoint
        } else {
            selectedPoint = nil
        }
    }

    // Clears only the drag overlay state — does NOT clear selectedPoint so that
    // a bar selection stays visible when a tap resolves without a completed drag.
    func clearDragState() {
        dragSource = nil; dragPosition = nil
    }

    func newGame() {
        autoEndTask?.cancel()
        autoPlayTask?.cancel()
        noMovesAvailable = false; resignedWinner = nil
        whiteScore = 0; blackScore = 0; scoreRecorded = false
        state = .makeInitial()
        dice = nil; selectedPoint = nil; allLegalMoves = []; history = []; pendingEndTurn = false
        flightInfo = nil; dragSource = nil; dragPosition = nil
        isSetupMode = false
        rollDice()
    }

    func rematch() {
        autoEndTask?.cancel()
        autoPlayTask?.cancel()
        noMovesAvailable = false; resignedWinner = nil
        scoreRecorded = false
        state = .makeInitial()
        dice = nil; selectedPoint = nil; allLegalMoves = []; history = []; pendingEndTurn = false
        flightInfo = nil; dragSource = nil; dragPosition = nil
        isSetupMode = false
        rollDice()
    }

    func enterSetupMode() {
        autoEndTask?.cancel()
        autoPlayTask?.cancel()
        noMovesAvailable = false; resignedWinner = nil
        flightInfo = nil
        dice = nil; selectedPoint = nil; allLegalMoves = []; history = []; pendingEndTurn = false
        state = .makeEmpty()
        isSetupMode = true
    }

    // Add/clear checkers during board setup. Each tap adds one of setupColor (up to 15).
    // Tapping opponent checkers clears the point; tapping at the 15-checker cap also clears.
    private func tapSetup(point: Int) {
        guard (1...24).contains(point) else { return }
        let mult = setupColor == .white ? 1 : -1
        let cur = state.points[point]
        if cur * mult < 0 || cur * mult >= 15 {
            state.points[point] = 0
        } else {
            state.points[point] += mult
        }
    }

    func clearSetupBoard() {
        state = .makeEmpty()
    }

    func startFromSetup(as player: Player) {
        autoEndTask?.cancel()
        autoPlayTask?.cancel()
        noMovesAvailable = false; resignedWinner = nil
        state.currentPlayer = player
        isSetupMode = false
        dice = nil; selectedPoint = nil; allLegalMoves = []; history = []; pendingEndTurn = false; flightInfo = nil
        rollDice()
    }

    func resign() {
        autoEndTask?.cancel()
        autoPlayTask?.cancel()
        noMovesAvailable = false
        resignedWinner = state.currentPlayer.opponent
        dice = nil; allLegalMoves = []; selectedPoint = nil; history = []; pendingEndTurn = false
        flightInfo = nil; dragSource = nil; dragPosition = nil
    }

    func confirmEndTurn() { endTurn() }

    private func finishTurn() {
        if let w = state.winner, !scoreRecorded {
            if w == .white { whiteScore += state.gameScore } else { blackScore += state.gameScore }
            scoreRecorded = true
            endTurn()
            return
        }
        guard let d = dice, !d.isDone else { pendingEndTurn = true; return }
        allLegalMoves = MoveGenerator.legalMoves(for: state, dice: d)
        if allLegalMoves.isEmpty { noMovesAvailable = true; scheduleAutoEnd(); return }
        if state.barCount(for: state.currentPlayer) > 0 {
            selectedPoint = state.currentPlayer.barPoint
        }
        scheduleAutoPlay(delay: 900)
    }

    private func uniqueForcedStep() -> CheckerMove? {
        guard let firstStep = allLegalMoves.first?.first else { return nil }
        return allLegalMoves.allSatisfy { $0.first?.from == firstStep.from && $0.first?.to == firstStep.to }
            ? firstStep : nil
    }

    private func scheduleAutoPlay(delay: Int) {
        guard let step = uniqueForcedStep() else { return }
        autoPlayTask?.cancel()
        autoPlayTask = Task {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            selectedPoint = step.from
            isAutoPlayInProgress = true
            commitMove(to: step.to)
            isAutoPlayInProgress = false
        }
    }

    private func scheduleAutoEnd() {
        autoEndTask?.cancel()
        autoEndTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            endTurn()
        }
    }

    private func endTurn() {
        autoEndTask?.cancel()
        autoPlayTask?.cancel()
        noMovesAvailable = false
        pendingEndTurn = false
        dice = nil; allLegalMoves = []; selectedPoint = nil; history = []; flightInfo = nil
        dragSource = nil; dragPosition = nil
        if state.winner == nil {
            state.currentPlayer = state.currentPlayer.opponent
            rollDice()
        }
    }
}
