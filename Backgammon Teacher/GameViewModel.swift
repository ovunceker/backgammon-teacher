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
    private var moveHistory: [CheckerMove] = []
    var flightInfo: FlightInfo? = nil
    private(set) var diceRollID: Int = 0
    var dragSource: Int? = nil
    var dragPosition: CGPoint? = nil
    private(set) var whiteScore: Int = 0
    private(set) var blackScore: Int = 0
    private var scoreRecorded: Bool = false
    private(set) var noMovesAvailable: Bool = false
    var cubeResponseMessage: String? = nil
    private(set) var resignedWinner: Player? = nil
    private(set) var droppedWinner: Player? = nil
    private var autoEndTask: Task<Void, Never>?
    private var autoPlayTask: Task<Void, Never>?
    private var isAutoPlayInProgress: Bool = false
    private(set) var lastAnalysis: MoveAnalysis? = nil
    private var analysisTask: Task<Void, Never>? = nil
    private(set) var openingDice: (white: Int, black: Int)? = nil
    private(set) var openingRollAnimID: Int = 0
    private var openingTask: Task<Void, Never>? = nil

    // MARK: Settings
    var advancedMode: Bool = UserDefaults.standard.bool(forKey: "advancedMode") {
        didSet {
            UserDefaults.standard.set(advancedMode, forKey: "advancedMode")
            // Toggling advanced off while waiting to roll → auto-roll so game isn't stuck
            if !advancedMode && pendingRoll && !pendingDouble { rollDice() }
        }
    }

    var coachMode: Bool = UserDefaults.standard.bool(forKey: "coachMode") {
        didSet { UserDefaults.standard.set(coachMode, forKey: "coachMode") }
    }

    // Default true: if key absent treat as enabled; if key present use stored value.
    var aiDoublingEnabled: Bool = (UserDefaults.standard.object(forKey: "aiDoublingEnabled") == nil)
        || UserDefaults.standard.bool(forKey: "aiDoublingEnabled") {
        didSet { UserDefaults.standard.set(aiDoublingEnabled, forKey: "aiDoublingEnabled") }
    }
    var vurKacRuleEnabled: Bool = UserDefaults.standard.bool(forKey: "vurKacRuleEnabled") {
        didSet { UserDefaults.standard.set(vurKacRuleEnabled, forKey: "vurKacRuleEnabled") }
    }
    var openingDiceAsFirst: Bool = UserDefaults.standard.bool(forKey: "openingDiceAsFirst") {
        didSet { UserDefaults.standard.set(openingDiceAsFirst, forKey: "openingDiceAsFirst") }
    }
    var professionalTimerEnabled: Bool = UserDefaults.standard.bool(forKey: "professionalTimerEnabled") {
        didSet { UserDefaults.standard.set(professionalTimerEnabled, forKey: "professionalTimerEnabled") }
    }
    var regularTimerEnabled: Bool = UserDefaults.standard.bool(forKey: "regularTimerEnabled") {
        didSet { UserDefaults.standard.set(regularTimerEnabled, forKey: "regularTimerEnabled") }
    }
    var vurKacViolation = false
    private var pendingOpeningDice: (Int, Int)? = nil

    // MARK: Professional timer
    private(set) var whiteGameSeconds: Int = 600   // 10 min reserve
    private(set) var blackGameSeconds: Int = 600
    private(set) var turnElapsedSeconds: Int = 0
    private var timerTask: Task<Void, Never>? = nil

    func startTurnTimer() {
        guard professionalTimerEnabled || regularTimerEnabled else { return }
        stopTurnTimer()
        turnElapsedSeconds = 0
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1000))
                guard !Task.isCancelled else { break }
                turnElapsedSeconds += 1
                if professionalTimerEnabled && turnElapsedSeconds > 12 {
                    if state.currentPlayer == .white {
                        whiteGameSeconds = max(0, whiteGameSeconds - 1)
                    } else {
                        blackGameSeconds = max(0, blackGameSeconds - 1)
                    }
                }
                if regularTimerEnabled && turnElapsedSeconds >= 12 {
                    resign()
                    break
                }
            }
        }
    }

    func stopTurnTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: Doubling cube + turn-start gate (active only when advancedMode is on)
    private(set) var cubeValue: Int = 1
    private(set) var cubeOwner: Player? = nil   // nil = centred
    private(set) var pendingDouble: Bool = false
    private(set) var pendingRoll: Bool = false   // true = player must Roll or Double before dice appear

    var canDouble: Bool {
        guard advancedMode, pendingRoll, !pendingDouble else { return false }
        guard effectiveWinner == nil, !isSetupMode else { return false }
        guard cubeValue < 64 else { return false }
        return cubeOwner == nil || cubeOwner == state.currentPlayer
    }

    var effectiveWinner: Player? { resignedWinner ?? droppedWinner ?? state.winner }
    var canRoll: Bool {
        guard state.winner == nil, resignedWinner == nil, droppedWinner == nil, !isSetupMode, !pendingDouble else { return false }
        if advancedMode && state.currentPlayer == .white { return pendingRoll }
        return dice == nil
    }
    var canUndo: Bool { !history.isEmpty && state.currentPlayer == .white }
    var pendingEndTurn: Bool = false

    var isSetupMode: Bool = false
    var setupColor: Player = .white
    var useFixedDice: Bool = false
    var setupDie1: Int = 1
    var setupDie2: Int = 6

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

    private func doOpeningRoll() {
        let w = Int.random(in: 1...6)
        let b = Int.random(in: 1...6)
        openingRollAnimID += 1
        openingDice = (white: w, black: b)
        openingTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if w == b {
                    doOpeningRoll()
                } else {
                    state.currentPlayer = w > b ? .white : .black
                    if openingDiceAsFirst {
                        pendingOpeningDice = (w, b)
                        // Keep openingDice visible; rollDice() will clear it when dice are ready
                    } else {
                        openingDice = nil
                    }
                    startTurn()
                }
            }
        }
    }

    private func startTurn() {
        let skipCube = openingDiceAsFirst && pendingOpeningDice != nil
        if advancedMode && state.currentPlayer == .white && !skipCube {
            pendingRoll = true
        } else if advancedMode && state.currentPlayer == .black && !skipCube {
            scheduleAICubeDecision()
        } else {
            // In advanced mode, canRoll requires pendingRoll for white;
            // set it here so rollDice() passes the guard (it clears it immediately).
            if advancedMode && state.currentPlayer == .white { pendingRoll = true }
            rollDice()
        }
    }

    func rollDice() {
        guard canRoll else { return }
        pendingRoll = false
        let d: Dice
        let usingOpeningValues: Bool
        if let (d1, d2) = pendingOpeningDice {
            pendingOpeningDice = nil
            openingDice = nil
            d = Dice(d1, d2)
            usingOpeningValues = true
        } else {
            d = Dice()
            usingOpeningValues = false
        }
        dice = d
        if !usingOpeningValues { diceRollID += 1 }
        allLegalMoves = filterVurKac(MoveGenerator.legalMoves(for: state, dice: d), from: state)
        if allLegalMoves.isEmpty {
            noMovesAvailable = true
            scheduleAutoEnd()
            return
        }
        if state.barCount(for: state.currentPlayer) > 0 {
            selectedPoint = state.currentPlayer.barPoint
        }
        if state.currentPlayer == .black {
            scheduleAIPlay(delay: 1500)
        } else {
            scheduleAutoPlay(delay: 1500)
        }
        startTurnTimer()
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
        if !moveHistory.isEmpty { moveHistory.removeLast() }
        guard let (prevState, prevDice) = history.popLast() else { return }
        state = prevState
        dice = prevDice
        selectedPoint = nil
        pendingEndTurn = false
        allLegalMoves = filterVurKac(MoveGenerator.legalMoves(for: state, dice: prevDice), from: state)
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
        moveHistory.append(step)
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
        autoEndTask?.cancel(); autoPlayTask?.cancel(); openingTask?.cancel()
        analysisTask?.cancel(); lastAnalysis = nil; analysisTask = nil
        stopTurnTimer(); whiteGameSeconds = 600; blackGameSeconds = 600; turnElapsedSeconds = 0
        noMovesAvailable = false; resignedWinner = nil; droppedWinner = nil; pendingRoll = false
        cubeValue = 1; cubeOwner = nil; pendingDouble = false; cubeResponseMessage = nil
        whiteScore = 0; blackScore = 0; scoreRecorded = false
        state = .makeInitial()
        dice = nil; selectedPoint = nil; allLegalMoves = []; history = []; moveHistory = []; pendingEndTurn = false
        flightInfo = nil; dragSource = nil; dragPosition = nil; openingDice = nil; pendingOpeningDice = nil
        isSetupMode = false
        doOpeningRoll()
    }

    func rematch() {
        autoEndTask?.cancel(); autoPlayTask?.cancel(); openingTask?.cancel()
        analysisTask?.cancel(); lastAnalysis = nil; analysisTask = nil
        stopTurnTimer(); whiteGameSeconds = 600; blackGameSeconds = 600; turnElapsedSeconds = 0
        noMovesAvailable = false; resignedWinner = nil; droppedWinner = nil; pendingRoll = false
        cubeValue = 1; cubeOwner = nil; pendingDouble = false; cubeResponseMessage = nil
        scoreRecorded = false
        state = .makeInitial()
        dice = nil; selectedPoint = nil; allLegalMoves = []; history = []; moveHistory = []; pendingEndTurn = false
        flightInfo = nil; dragSource = nil; dragPosition = nil; openingDice = nil; pendingOpeningDice = nil
        isSetupMode = false
        doOpeningRoll()
    }

    func enterSetupMode() {
        autoEndTask?.cancel(); autoPlayTask?.cancel(); openingTask?.cancel()
        analysisTask?.cancel(); lastAnalysis = nil; analysisTask = nil
        noMovesAvailable = false; resignedWinner = nil; droppedWinner = nil; pendingRoll = false
        cubeValue = 1; cubeOwner = nil; pendingDouble = false; cubeResponseMessage = nil
        flightInfo = nil
        dice = nil; selectedPoint = nil; allLegalMoves = []; history = []; moveHistory = []; pendingEndTurn = false
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

    func resetToDefaultBoard() {
        state = .makeInitial()
    }

    func startFromSetup(as player: Player) {
        autoEndTask?.cancel(); autoPlayTask?.cancel(); openingTask?.cancel()
        analysisTask?.cancel(); lastAnalysis = nil; analysisTask = nil
        openingDice = nil; pendingOpeningDice = nil
        noMovesAvailable = false; resignedWinner = nil; droppedWinner = nil; pendingRoll = false
        state.currentPlayer = player
        isSetupMode = false
        dice = nil; selectedPoint = nil; allLegalMoves = []; history = []; moveHistory = []; pendingEndTurn = false; flightInfo = nil
        if useFixedDice {
            rollFixedDice()
        } else {
            startTurn()
        }
    }

    private func rollFixedDice() {
        let d = Dice(setupDie1, setupDie2)
        dice = d
        diceRollID += 1
        allLegalMoves = filterVurKac(MoveGenerator.legalMoves(for: state, dice: d), from: state)
        if allLegalMoves.isEmpty {
            noMovesAvailable = true
            if state.currentPlayer == .black { scheduleAutoEnd() } else { pendingEndTurn = true }
            return
        }
        if state.barCount(for: state.currentPlayer) > 0 {
            selectedPoint = state.currentPlayer.barPoint
        }
        if state.currentPlayer == .black {
            scheduleAIPlay(delay: 900)
        } else {
            scheduleAutoPlay(delay: 1500)
        }
    }

    func offerDouble() {
        guard canDouble else { return }
        pendingDouble = true
        // Black (AI) auto-responds to white's double offer
        if state.currentPlayer == .white { scheduleAICubeResponse() }
    }

    func acceptDouble() {
        cubeValue *= 2
        cubeOwner = state.currentPlayer.opponent   // acceptor (opponent) now owns it
        pendingDouble = false
        // If black was the offerer, continue its turn by rolling
        if state.currentPlayer == .black { rollDice() }
    }

    func dropDouble() {
        stopTurnTimer()
        analysisTask?.cancel(); lastAnalysis = nil; analysisTask = nil
        let winner = state.currentPlayer  // offerer wins when opponent drops
        let pts = cubeValue
        if winner == .white { whiteScore += pts } else { blackScore += pts }
        scoreRecorded = true
        droppedWinner = winner   // allows rematch, unlike resignedWinner
        pendingDouble = false; pendingRoll = false; cubeResponseMessage = nil
        dice = nil; allLegalMoves = []; selectedPoint = nil; history = []; moveHistory = []; pendingEndTurn = false
        flightInfo = nil; dragSource = nil; dragPosition = nil
    }

    func resign() {
        stopTurnTimer()
        autoEndTask?.cancel()
        autoPlayTask?.cancel()
        analysisTask?.cancel(); lastAnalysis = nil; analysisTask = nil
        noMovesAvailable = false; pendingRoll = false
        let winner = state.currentPlayer.opponent
        if winner == .white { whiteScore += cubeValue } else { blackScore += cubeValue }
        scoreRecorded = true
        resignedWinner = winner
        dice = nil; allLegalMoves = []; selectedPoint = nil; history = []; moveHistory = []; pendingEndTurn = false
        flightInfo = nil; dragSource = nil; dragPosition = nil
    }

    func confirmEndTurn() {
        stopTurnTimer()
        if vurKacRuleEnabled, state.currentPlayer == .white,
           let (preTurnState, preTurnDice) = history.first {
            let violation = (1...6).contains(where: { p in
                preTurnState.points[p] == -1 && state.points[p] == 0
            })
            if violation {
                let steps = moveHistory
                let histSnap = history
                history = []; moveHistory = []
                selectedPoint = nil; pendingEndTurn = false
                animateRevertToTurnStart(steps: steps, historySnap: histSnap)
                return
            }
        }
        analysisTask?.cancel()
        analysisTask = nil
        if coachMode, let (preTurnState, preTurnDice) = history.first, state.winner == nil {
            let playerFinal = state
            lastAnalysis = nil
            analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
                let result = MoveExplainer.analyze(
                    preTurnState: preTurnState,
                    dice: preTurnDice,
                    playerFinalState: playerFinal
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in self?.lastAnalysis = result }
            }
        }
        endTurn()
    }

    private func finishTurn() {
        if let w = state.winner, !scoreRecorded {
            let pts = state.score(advanced: advancedMode) * cubeValue
            if w == .white { whiteScore += pts } else { blackScore += pts }
            scoreRecorded = true
            endTurn()
            return
        }
        guard let d = dice, !d.isDone else {
            if state.currentPlayer == .black { scheduleAutoEnd() } else { pendingEndTurn = true }
            return
        }
        allLegalMoves = filterVurKac(MoveGenerator.legalMoves(for: state, dice: d), from: state)
        if allLegalMoves.isEmpty {
            noMovesAvailable = true
            scheduleAutoEnd()
            return
        }
        if state.barCount(for: state.currentPlayer) > 0 {
            selectedPoint = state.currentPlayer.barPoint
        }
        if state.currentPlayer == .black {
            scheduleAIPlay(delay: 900)
        } else {
            scheduleAutoPlay(delay: 900)
        }
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

    private func animateRevertToTurnStart(steps: [CheckerMove], historySnap: [(BoardState, Dice)]) {
        Task { @MainActor in
            for (i, step) in steps.reversed().enumerated() {
                let snapIdx = historySnap.count - 1 - i
                guard snapIdx >= 0 else { break }
                let (prevState, prevDice) = historySnap[snapIdx]
                // Restore state first so the board reflects the reverted position
                state = prevState
                dice = prevDice
                // Flight animation: checker flies backwards (original to → original from)
                flightInfo = FlightInfo(from: step.to, to: step.from, isWhite: true)
                try? await Task.sleep(for: .milliseconds(600))
            }
            // Final cleanup
            flightInfo = nil
            dragSource = nil; dragPosition = nil
            noMovesAvailable = false
            if let d = dice {
                allLegalMoves = filterVurKac(MoveGenerator.legalMoves(for: state, dice: d), from: state)
            }
            vurKacViolation = true
        }
    }

    private func filterVurKac(_ moves: [Move], from boardBefore: BoardState) -> [Move] {
        guard vurKacRuleEnabled else { return moves }
        let player = boardBefore.currentPlayer
        let homeRange = player == .white ? 1...6 : 19...24
        let sign = player == .white ? 1 : -1
        return moves.filter { move in
            var hitPoints: Set<Int> = []
            var s = boardBefore
            for step in move {
                if homeRange.contains(step.to) && s.points[step.to] == -sign {
                    hitPoints.insert(step.to)
                }
                s = s.applying(step)
            }
            return hitPoints.allSatisfy { s.points[$0] * sign > 0 }
        }
    }

    private func scheduleAIPlay(delay: Int) {
        guard !allLegalMoves.isEmpty else { return }
        autoPlayTask?.cancel()
        autoPlayTask = Task {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            guard let move = AIPlayer.bestMove(for: state, moves: allLegalMoves, cube: cubeValue, cubeOwner: cubeOwner),
                  let step = move.first else { return }
            selectedPoint = step.from
            isAutoPlayInProgress = true
            commitMove(to: step.to)
            isAutoPlayInProgress = false
        }
    }

    // Black decides whether to offer a double before rolling.
    // Uses equity (not pWin) because the model's absolute win probabilities are
    // colour-biased: BLACK's equity at the neutral starting position is ~0.92.
    // Doubling window: equity in [1.5, 2.5] = clearly ahead but not playing for gammon.
    // recalibrate lower bound after retrain when colour bias is eliminated.
    private func scheduleAICubeDecision() {
        autoPlayTask?.cancel()
        autoPlayTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            let canOffer = aiDoublingEnabled
                && (cubeOwner == nil || cubeOwner == .black)
                && cubeValue < 64
            if canOffer,
               let (equity, _) = AIPlayer.equityAndProbs(for: state, player: .black,
                                                         cube: cubeValue, cubeOwner: cubeOwner) {
                if equity >= 1.5 && equity <= 2.5 {
                    pendingDouble = true   // white (human) decides to accept or drop
                } else {
                    rollDice()
                }
            } else {
                rollDice()
            }
        }
    }

    // Black auto-responds to white's double offer.
    // Drop when BLACK's equity is below 0.3 — clearly losing even accounting for
    // the model's colour bias (neutral ≈ 0.92, so 0.3 means genuinely behind).
    // recalibrate after retrain.
    private func scheduleAICubeResponse() {
        autoPlayTask?.cancel()
        autoPlayTask = Task {
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            let drops: Bool
            if let (equity, _) = AIPlayer.equityAndProbs(for: state, player: .black,
                                                         cube: cubeValue, cubeOwner: cubeOwner) {
                drops = equity < 0.3
            } else {
                drops = false
            }
            pendingDouble = false
            cubeResponseMessage = drops ? "Denied" : "Accepted"
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            cubeResponseMessage = nil
            if drops { dropDouble() } else { acceptDouble() }
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
        pendingEndTurn = false; pendingRoll = false
        dice = nil; allLegalMoves = []; selectedPoint = nil; history = []; moveHistory = []; flightInfo = nil
        dragSource = nil; dragPosition = nil
        if state.winner == nil {
            state.currentPlayer = state.currentPlayer.opponent
            startTurn()
        }
    }
}
