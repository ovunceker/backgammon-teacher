import SwiftUI

// Top row (L→R): 13–18 | BAR | 19–24    Bottom row (L→R): 12–7 | BAR | 6–1
private let topLeft  = [13, 14, 15, 16, 17, 18]; private let topRight = [19, 20, 21, 22, 23, 24]
private let botLeft  = [12, 11, 10,  9,  8,  7]; private let botRight = [ 6,  5,  4,  3,  2,  1]

// Panel colour palette — enum so it is never a stored property on a View struct.
private enum PC {
    static let cream    = Color(red: 0.96, green: 0.90, blue: 0.70)
    static let dim      = Color(red: 0.65, green: 0.54, blue: 0.38)
    static let bg       = Color(red: 0.17, green: 0.09, blue: 0.03)
    static let green    = Color(red: 0.14, green: 0.40, blue: 0.18)
    static let red      = Color(red: 0.50, green: 0.08, blue: 0.08)
    static let brown    = Color(red: 0.34, green: 0.20, blue: 0.07)
    static let tan      = Color(red: 0.58, green: 0.50, blue: 0.32)
}

// MARK: - BoardView

struct BoardView: View {
    @Environment(GameViewModel.self) private var vm

    @State private var diceDisplayValues: [Int] = []
    @State private var diceRolling = false
    @State private var diceAnimTask: Task<Void, Never>?
    @State private var openingDisplayValues: (white: Int, black: Int) = (1, 1)
    @State private var openingRolling = false
    @State private var openingAnimTask: Task<Void, Never>?
    @State private var openingDicePositioned = false   // true once both dice have frozen positions
    @State private var openingWhiteDieX: CGFloat = 0
    @State private var openingBlackDieX: CGFloat = 0
    @State private var capturedXOff: CGFloat = 40
    @State private var capturedDSz: CGFloat = 30
    @State private var openingFlyTask: Task<Void, Never>?
    @State private var showSettings = false
    private struct AnalysisPresentation: Identifiable {
        let id = UUID()
        let analysis: MoveAnalysis
    }
    @State private var presentedAnalysis: AnalysisPresentation? = nil
    @State private var showVurKacToast = false
    @State private var vurKacToastTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.06, blue: 0.02).ignoresSafeArea()
            GeometryReader { geo in
                // Landscape: board fills the height; controls live in a right-side panel.
                let leftW:  CGFloat = 0
                let panelW: CGFloat = 148
                let pad:    CGFloat = 8
                let boardH  = geo.size.height - pad * 2
                let barW    = max(boardH * 0.065, 20)
                let boardW  = geo.size.width - leftW - panelW - barW - pad * 3
                let ptH     = (boardH - 20) / 2
                let ptW     = (boardW - barW) / 12
                let cSz     = min(ptW * 0.84, ptH / 4.6)

                HStack(alignment: .center, spacing: 0) {
                    Color.clear.frame(width: leftW)
                    boardCanvas(W: boardW, ptW: ptW, ptH: ptH, barW: barW, cSz: cSz)
                    boreOffTray(trayW: barW, ptH: ptH, cSz: cSz)
                    controlPanel
                        .frame(width: panelW)
                        .padding(.leading, pad)
                }
                .padding(pad)
            }
        }
        .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 6) {
                if vm.professionalTimerEnabled {
                    let elapsed  = vm.turnElapsedSeconds
                    let _ = vm.state.currentPlayer == .white && vm.dice != nil
                    let bTurn    = vm.state.currentPlayer == .black && vm.dice != nil
                    // Black clock — near top (adjust .padding(.top, N) to move up/down)
                    clockBadge(seconds: vm.blackGameSeconds, burning: bTurn && elapsed > 12)
                        .padding(.leading, -60)
                }
                Spacer()
                if vm.professionalTimerEnabled || vm.regularTimerEnabled {
                    let elapsed = vm.turnElapsedSeconds
                    let wTurn   = vm.state.currentPlayer == .white && vm.dice != nil
                    // 12s turn timer — white's move only, single line
                    if wTurn {
                        let remaining = max(0, 12 - elapsed)
                        let over = elapsed > 12
                        let tc: Color = over ? .orange : remaining <= 4 ? .red : remaining <= 8 ? .yellow : PC.cream
                        HStack(spacing: 4) {
                            Image(systemName: over ? "flame.fill" : "timer")
                                .font(.system(size: 9, weight: .bold))
                            Text(over ? "+\(elapsed - 12)s" : "\(remaining)s")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                        }
                        .foregroundStyle(tc)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .overlay(Capsule().stroke(tc.opacity(0.35), lineWidth: 1))
                        .lineLimit(1).fixedSize()
                        .padding(.leading, -60)
                    }
                    // White/black game clocks — professional timer only
                    if vm.professionalTimerEnabled {
                        clockBadge(seconds: vm.whiteGameSeconds, burning: wTurn && elapsed > 12)
                            .padding(.leading, -60)
                    }
                }
                // Settings gear — sits off-screen left as a peeking tab
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(PC.dim)
                        .padding(9)
                        .background(PC.bg.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(PC.cream.opacity(0.10), lineWidth: 1))
                }
                .padding(.leading, -40)
            }
            .padding(.vertical, 9)
            .frame(maxHeight: .infinity)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(vm)
        }
        .sheet(item: $presentedAnalysis) { p in
            ExplanationSheet(analysis: p.analysis)
        }
        .onChange(of: vm.vurKacViolation) { _, newVal in
            guard newVal else { return }
            vm.vurKacViolation = false
            vurKacToastTask?.cancel()
            showVurKacToast = true
            vurKacToastTask = Task {
                try? await Task.sleep(for: .milliseconds(2000))
                guard !Task.isCancelled else { return }
                showVurKacToast = false
            }
        }
        .onChange(of: vm.diceRollID) { _, _ in
            guard let dice = vm.dice else { return }
            diceAnimTask?.cancel()
            diceRolling = true
            let count = dice.remaining.count
            // Seed display immediately so the first frame isn't blank
            diceDisplayValues = (0..<count).map { _ in Int.random(in: 1...6) }
            diceAnimTask = Task {
                for _ in 0..<8 {
                    guard !Task.isCancelled else { return }
                    diceDisplayValues = (0..<count).map { _ in Int.random(in: 1...6) }
                    try? await Task.sleep(for: .milliseconds(60))
                }
                guard !Task.isCancelled else { return }
                diceRolling = false
            }
        }
        .onChange(of: vm.openingRollAnimID) { _, _ in
            guard vm.openingDice != nil else { return }
            openingFlyTask?.cancel()
            openingDicePositioned = false
            openingAnimTask?.cancel()
            openingRolling = true
            openingDisplayValues = (Int.random(in: 1...6), Int.random(in: 1...6))
            openingAnimTask = Task {
                for _ in 0..<8 {
                    guard !Task.isCancelled else { return }
                    openingDisplayValues = (Int.random(in: 1...6), Int.random(in: 1...6))
                    try? await Task.sleep(for: .milliseconds(60))
                }
                guard !Task.isCancelled else { return }
                openingRolling = false
            }
        }
        .onChange(of: vm.openingDice == nil) { _, isNil in
            if isNil { openingFlyTask?.cancel(); openingDicePositioned = false }
        }
        .onChange(of: openingRolling) { _, newVal in
            guard !newVal, let od = vm.openingDice, od.white != od.black else { return }
            openingFlyTask?.cancel()
            openingDicePositioned = false
            openingFlyTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                // Compute final side-by-side positions (both frozen from current geometry)
                // Both dice slide simultaneously — winner moves spacing/2 outward, loser crosses the board
                let whiteWins = od.white > od.black
                let spacing = capturedDSz + 4
                let cx = capturedXOff          // centre of winner's current position
                // Final positions: pair centred on cx, on the winner's side
                // Black wins → left side: white(small) outer-left, black(big) inner-left
                // White wins → right side: white(big) inner-right, black(small) outer-right
                let wFinal: CGFloat = whiteWins ?  (cx - spacing / 2) : -(cx + spacing / 2)
                let bFinal: CGFloat = whiteWins ?  (cx + spacing / 2) : -(cx - spacing / 2)
                // Place both at their current starting positions before animating
                openingWhiteDieX =  capturedXOff
                openingBlackDieX = -capturedXOff
                openingDicePositioned = true
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    openingWhiteDieX = wFinal
                    openingBlackDieX = bFinal
                }
                // Leave positioned so dice stay put until game starts
            }
        }
    }

    // MARK: Board

    private func clockBadge(seconds: Int, burning: Bool) -> some View {
        let low = seconds < 60
        let color: Color = low ? .red : burning ? .orange : PC.cream
        return HStack(spacing: 4) {
            Image(systemName: "clock.fill").font(.system(size: 9, weight: .bold))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 11, weight: .black, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
        .lineLimit(1).fixedSize()
    }

    private func boardCanvas(W: CGFloat, ptW: CGFloat, ptH: CGFloat, barW: CGFloat, cSz: CGFloat) -> some View {
        ZStack {
            // Board surface — clipped so bar/point content can't bleed past the rounded corners.
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.42, green: 0.24, blue: 0.10))
                HStack(spacing: 0) {
                    halfPanel(top: topLeft, bot: botLeft, ptW: ptW, ptH: ptH, barW: barW, cSz: cSz)
                    barPanel(barW: barW, ptW: ptW, ptH: ptH, cSz: cSz)
                    halfPanel(top: topRight, bot: botRight, ptW: ptW, ptH: ptH, barW: barW, cSz: cSz)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)

            // Overlays sit outside the clip so flight animation and drag disc can extend freely.
            if let od = vm.openingDice {
                let dSz: CGFloat = min(ptW * 0.74, 40)
                let xOff: CGFloat = ptW * 3 + barW / 2
                let wVal = openingRolling ? openingDisplayValues.white : od.white
                let bVal = openingRolling ? openingDisplayValues.black : od.black
                // Capture geometry once so task can read it before animation starts
                Color.clear.frame(width: 0, height: 0)
                    .task(id: xOff) { capturedXOff = xOff }
                    .task(id: dSz)  { capturedDSz  = dSz  }
                // Both dice always visible; positions are frozen state vars once animation begins
                DiceFaceView(value: wVal, size: dSz)
                    .offset(x: openingDicePositioned ? openingWhiteDieX : xOff)
                DiceFaceView(value: bVal, size: dSz)
                    .offset(x: openingDicePositioned ? openingBlackDieX : -xOff)
                if !openingRolling {
                    let label = od.white > od.black ? "YOU START" : od.black > od.white ? "OPPONENT STARTS" : "REROLL"
                    Text(label)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(PC.cream)
                        .kerning(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(PC.bg.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            // Hide overlay while white's double offer awaits AI response (pendingDouble + white offered)
            let showOverlay = vm.openingDice == nil && (
                vm.cubeResponseMessage != nil ||
                (vm.pendingDouble && vm.state.currentPlayer == .black) ||
                (!vm.pendingDouble && (vm.dice != nil || vm.pendingRoll))
            )
            if showOverlay { boardOverlay(ptW: ptW, barW: barW) }
            CheckerFlightOverlay(ptW: ptW, ptH: ptH, barW: barW, cSz: cSz)
            if let pos = vm.dragPosition {
                dragDisc(isWhite: vm.state.currentPlayer == .white, cSz: cSz)
                    .position(pos)
                    .allowsHitTesting(false)
            }
            if showVurKacToast {
                Text("HIT & RUN NOT ALLOWED")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(PC.cream)
                    .kerning(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PC.bg.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: W, height: ptH * 2 + 20)
        .coordinateSpace(.named("board"))
    }

    private func halfPanel(top: [Int], bot: [Int], ptW: CGFloat, ptH: CGFloat, barW: CGFloat, cSz: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(top, id: \.self) { PointView(point: $0, isTop: true,  ptW: ptW, ptH: ptH, barW: barW, cSz: cSz) }
            }
            Spacer(minLength: 20)
            HStack(spacing: 0) {
                ForEach(bot, id: \.self) { PointView(point: $0, isTop: false, ptW: ptW, ptH: ptH, barW: barW, cSz: cSz) }
            }
        }
        .frame(width: ptW * 6)
    }

    private func barPanel(barW: CGFloat, ptW: CGFloat, ptH: CGFloat, cSz: CGFloat) -> some View {
        VStack {
            barCheckers(.black, barW: barW, ptW: ptW, ptH: ptH, cSz: cSz)
            Spacer()
            barCheckers(.white, barW: barW, ptW: ptW, ptH: ptH, cSz: cSz)
        }
        .padding(.vertical, 6)
        .frame(width: barW, height: ptH * 2 + 20)
        .background(Color(red: 0.26, green: 0.14, blue: 0.05))
    }

    @ViewBuilder
    private func barCheckers(_ player: Player, barW: CGFloat, ptW: CGFloat, ptH: CGFloat, cSz: CGFloat) -> some View {
        let count = player == .white ? vm.state.whiteBar : vm.state.blackBar
        let pt    = player.barPoint
        let sz    = min(barW * 0.78, cSz)
        let boardH = ptH * 2 + 20
        // Hide the dragged checker while it is floating
        let displayCount = vm.dragSource == pt ? max(0, count - 1) : count
        let findPoint: (CGPoint) -> Int? = { pos in
            for p in 1...24 {
                let cx: CGFloat
                switch p {
                case 13...18: cx = CGFloat(p - 13) * ptW + ptW / 2
                case 19...24: cx = ptW * 6 + barW + CGFloat(p - 19) * ptW + ptW / 2
                case 7...12:  cx = CGFloat(12 - p) * ptW + ptW / 2
                case 1...6:   cx = ptW * 6 + barW + CGFloat(6 - p) * ptW + ptW / 2
                default:      continue
                }
                let isTopRow = (13...24).contains(p)
                let yMin: CGFloat = isTopRow ? 0 : ptH + 20
                let yMax: CGFloat = isTopRow ? ptH : boardH
                if abs(pos.x - cx) <= ptW / 2 && pos.y >= yMin && pos.y <= yMax { return p }
            }
            return nil
        }
        VStack(spacing: 2) {
            ForEach(0..<min(displayCount, 3), id: \.self) { _ in
                Circle()
                    .fill(player == .white ? Color.white : Color(white: 0.12))
                    .overlay(Circle().stroke(player == .white ? Color.gray : Color(white: 0.55), lineWidth: 1))
                    .frame(width: sz, height: sz)
            }
            if displayCount > 3 { Text("+\(displayCount - 3)").font(.caption2.bold()).foregroundColor(.white) }
        }
        .padding(3)
        .background(vm.selectedPoint == pt ? Color.yellow.opacity(0.45) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("board"))
                .onChanged { val in
                    guard count > 0 else { return }
                    let moved = hypot(val.translation.width, val.translation.height)
                    guard moved > 12 else { return }
                    if vm.dragSource == nil {
                        guard vm.selectableSources.contains(pt) else { return }
                        vm.dragSource = pt
                        vm.selectedPoint = pt
                    } else if vm.dragSource != pt { return }
                    vm.dragPosition = val.location
                }
                .onEnded { val in
                    guard count > 0 else { return }
                    let moved = hypot(val.translation.width, val.translation.height)
                    if moved <= 12 {
                        vm.clearDragState()   // preserve selectedPoint
                        vm.tap(point: pt)
                        return
                    }
                    guard vm.dragSource == pt else { vm.cancelDrag(); return }
                    if let dest = findPoint(val.location), vm.legalDestinations.contains(dest) {
                        vm.drop(to: dest)
                    } else {
                        vm.cancelDrag()
                    }
                }
        )
    }

    // MARK: On-board dice + action buttons

    // Dice and Undo/Done buttons centred in the right half (white) or left half (black).
    private func boardOverlay(ptW: CGFloat, barW: CGFloat) -> some View {
        let isWhite: Bool
        if vm.cubeResponseMessage != nil {
            isWhite = false  // show on black's side
        } else if vm.pendingDouble {
            isWhite = vm.state.currentPlayer.opponent == .white
        } else {
            isWhite = vm.state.currentPlayer == .white
        }
        let dSz: CGFloat = min(ptW * 0.74, 40)
        let xOff = ptW * 3 + barW / 2

        return VStack(spacing: 10) {
            if let msg = vm.cubeResponseMessage {
                // AI responded to white's double offer — same look as ACCEPT/DROP buttons
                let tint: Color = msg == "Accepted"
                    ? Color(red: 0.14, green: 0.42, blue: 0.18)
                    : Color(red: 0.58, green: 0.08, blue: 0.08)
                Text(msg)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.96, green: 0.90, blue: 0.70))
                    .kerning(2)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(LinearGradient(
                                colors: [tint.opacity(0.80), tint],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1))
                    )
                    .shadow(color: tint.opacity(0.55), radius: 4, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.30), radius: 2, x: 0, y: 1)
            } else if vm.pendingDouble {
                // Cube offered by black — white (human) chooses
                Text("CUBE OFFERED  ×\(vm.cubeValue * 2)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(PC.cream).kerning(1.5)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 10) {
                    gameButton("ACCEPT", tint: Color(red: 0.14, green: 0.42, blue: 0.18)) { vm.acceptDouble() }
                    gameButton("DROP",   tint: Color(red: 0.58, green: 0.08, blue: 0.08)) { vm.dropDouble() }
                }
            } else if vm.pendingRoll {
                // Start-of-turn gate: player chooses to double or roll
                if vm.canDouble {
                    gameButton("DOUBLE  ×\(vm.cubeValue * 2)",
                               tint: Color(red: 0.48, green: 0.32, blue: 0.06)) { vm.offerDouble() }
                }
                gameButton("ROLL", tint: Color(red: 0.14, green: 0.42, blue: 0.18)) { vm.rollDice() }
            } else {
                // Normal mid-turn: dice + undo/done
                if let d = vm.dice, !d.remaining.isEmpty {
                    let displayVals = diceRolling ? diceDisplayValues : d.remaining
                    diceContent(values: displayVals.isEmpty ? d.remaining : displayVals, dSz: dSz)
                }
                if vm.noMovesAvailable {
                    Text("NO AVAILABLE MOVES")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(PC.cream).kerning(1.5)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(PC.cream.opacity(0.15), lineWidth: 1))
                } else if vm.canUndo || vm.pendingEndTurn {
                    HStack(spacing: 10) {
                        if vm.canUndo {
                            gameButton("UNDO", tint: Color(red: 0.58, green: 0.08, blue: 0.08)) { vm.undoStep() }
                        }
                        if vm.pendingEndTurn {
                            gameButton("DONE", tint: Color(red: 0.14, green: 0.42, blue: 0.18)) { vm.confirmEndTurn() }
                        }
                    }
                }
            }
        }
        .offset(x: isWhite ? xOff : -xOff)
    }

    private func dragDisc(isWhite: Bool, cSz: CGFloat) -> some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [isWhite ? Color(white: 1.0) : Color(white: 0.42),
                         isWhite ? Color(white: 0.68) : Color(white: 0.07)],
                center: UnitPoint(x: 0.33, y: 0.28),
                startRadius: 0, endRadius: cSz * 0.62
            ))
            Circle().stroke(isWhite ? Color(white: 0.52) : Color(white: 0.58), lineWidth: 1.5)
            Ellipse()
                .fill(Color.white.opacity(isWhite ? 0.70 : 0.25))
                .frame(width: cSz * 0.36, height: cSz * 0.20)
                .offset(x: -cSz * 0.09, y: -cSz * 0.17)
        }
        .frame(width: cSz * 1.18, height: cSz * 1.18)
        .shadow(color: .black.opacity(0.55), radius: 6, x: 0, y: 3)
    }

    private func gameButton(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Color(red: 0.96, green: 0.90, blue: 0.70))
                .kerning(2)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(
                            colors: [tint.opacity(0.80), tint],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1))
                )
        }
        .shadow(color: tint.opacity(0.55), radius: 4, x: 0, y: 2)
        .shadow(color: .black.opacity(0.30), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private func diceContent(values vals: [Int], dSz: CGFloat) -> some View {
        if vals.count <= 2 {
            HStack(spacing: 6) {
                ForEach(vals.indices, id: \.self) { DiceFaceView(value: vals[$0], size: dSz) }
            }
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    DiceFaceView(value: vals[0], size: dSz)
                    DiceFaceView(value: vals[1], size: dSz)
                }
                HStack(spacing: 6) {
                    DiceFaceView(value: vals[2], size: dSz)
                    if vals.count > 3 { DiceFaceView(value: vals[3], size: dSz) }
                }
            }
        }
    }

    // MARK: Borne-off tray

    private func boreOffTray(trayW: CGFloat, ptH: CGFloat, cSz: CGFloat) -> some View {
        VStack(spacing: 0) {
            boreOffSection(player: .black, trayW: trayW, ptH: ptH)
            Spacer(minLength: 20)
            boreOffSection(player: .white, trayW: trayW, ptH: ptH)
        }
        .frame(width: trayW, height: ptH * 2 + 20)
        .background(Color(red: 0.26, green: 0.14, blue: 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }

    @ViewBuilder
    private func boreOffSection(player: Player, trayW: CGFloat, ptH: CGFloat) -> some View {
        let count   = player == .white ? vm.state.whiteBorneOff : vm.state.blackBorneOff
        // Slice sizing: 15 slices + 14 gaps of 1pt + 10pt padding = ptH exactly at 15 checkers.
        let sliceH: CGFloat = max(4, (ptH - 24) / 15)
        let sliceW: CGFloat = trayW * 0.80
        let isWhite = player == .white
        ZStack(alignment: isWhite ? .bottom : .top) {
            Color.clear.frame(height: ptH)
            if count > 0 {
                VStack(spacing: 1) {
                    ForEach(0..<count, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(
                                colors: isWhite
                                    ? [Color(white: 0.98), Color(white: 0.80)]
                                    : [Color(white: 0.30), Color(white: 0.08)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .overlay(RoundedRectangle(cornerRadius: 2)
                                .stroke(isWhite ? Color(white: 0.58) : Color(white: 0.40), lineWidth: 0.5))
                            .frame(width: sliceW, height: sliceH)
                    }
                }
                .padding(.vertical, 5)
            }
        }
    }

    // MARK: Control panel (right side)

    @ViewBuilder
    private var controlPanel: some View {
        VStack(spacing: 11) {
            if vm.isSetupMode {
                panelLabel("BOARD SETUP")
                HStack(spacing: 6) {
                    setupColorButton(.white, label: "White")
                    setupColorButton(.black, label: "Black")
                }
                Text("Tap a point to add a checker. Tap at max (15) or opponent to clear.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(PC.dim)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    panelButton("DEFAULT", tint: PC.brown) { vm.resetToDefaultBoard() }
                    panelButton("CLEAR",   tint: PC.red)   { vm.clearSetupBoard() }
                }
                Rectangle().fill(PC.cream.opacity(0.10)).frame(height: 1)
                Toggle(isOn: Binding(get: { vm.useFixedDice }, set: { vm.useFixedDice = $0 })) {
                    Text("FIXED DICE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(PC.cream)
                        .kerning(1)
                }
                .toggleStyle(SwitchToggleStyle(tint: PC.brown))
                if vm.useFixedDice {
                    HStack(spacing: 8) {
                        dieSelector(value: Binding(get: { vm.setupDie1 }, set: { vm.setupDie1 = $0 }))
                        Text("—")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(PC.dim)
                        dieSelector(value: Binding(get: { vm.setupDie2 }, set: { vm.setupDie2 = $0 }))
                    }
                    .frame(maxWidth: .infinity)
                }
                Rectangle().fill(PC.cream.opacity(0.10)).frame(height: 1)
                panelLabel("START AS")
                panelButton("WHITE", tint: PC.tan)   { vm.startFromSetup(as: .white) }
                panelButton("BLACK", tint: PC.green) { vm.startFromSetup(as: .black) }

            } else if let w = vm.effectiveWinner {
                let resigned = vm.resignedWinner != nil
                let dropped  = vm.droppedWinner  != nil
                Text(resigned
                     ? "\(w.opponent == .white ? "WHITE" : "BLACK") RESIGNED"
                     : "\(w == .white ? "WHITE" : "BLACK") WINS")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(PC.cream)
                    .kerning(1.5)
                    .frame(maxWidth: .infinity)
                scoreChip
                if !resigned {
                    panelButton("REMATCH", tint: PC.green) { vm.rematch() }
                }
                panelButton("NEW GAME", tint: PC.red) { vm.newGame() }
                let _ = dropped   // suppress unused-variable warning

            } else if vm.dice == nil {
                panelButton("NEW GAME",    tint: PC.green) { vm.newGame() }
                panelButton("SETUP BOARD", tint: PC.brown) { vm.enterSetupMode() }
                panelButton("RESIGN",      tint: PC.red)   { vm.resign() }

            } else {
                panelButton("SETUP BOARD", tint: PC.brown) { vm.enterSetupMode() }
                panelButton("RESIGN",      tint: PC.red)   { vm.resign() }
            }

            Spacer()
            if vm.coachMode && vm.pendingRoll && vm.state.currentPlayer == .white,
               let eq = vm.preTurnEquity {
                cubePreRollWidget(equity: eq)
            }
            if vm.coachMode, let analysis = vm.lastAnalysis {
                analysisBanner(analysis: analysis)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(PC.bg)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(PC.cream.opacity(0.10), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
    }

    private var scoreChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(white: 0.93))
                .overlay(Circle().stroke(Color(white: 0.60), lineWidth: 0.75))
                .frame(width: 12, height: 12)
            Text("\(vm.whiteScore)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(PC.cream)
            Text(":")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PC.dim)
            Text("\(vm.blackScore)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(PC.cream)
            Circle()
                .fill(Color(white: 0.13))
                .overlay(Circle().stroke(Color(white: 0.50), lineWidth: 0.75))
                .frame(width: 12, height: 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(PC.cream.opacity(0.08), lineWidth: 1))
    }

    private func panelLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundStyle(PC.dim)
            .kerning(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func panelButton(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(PC.cream)
                .kerning(1.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(
                            colors: [tint.opacity(0.80), tint],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.13), lineWidth: 1))
                )
        }
        .shadow(color: tint.opacity(0.45), radius: 3, x: 0, y: 2)
        .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 1)
    }

    private func cubePreRollWidget(equity: Float) -> some View {
        let (label, title, color): (String, String, Color) = {
            if equity > 0.75 {
                return ("TOO GOOD", "Play for the gammon — don't double yet",
                        Color(red: 0.20, green: 0.70, blue: 0.25))
            } else if equity > 0.35 {
                return ("DOUBLE", "Strong position — consider offering the cube",
                        Color(red: 0.20, green: 0.70, blue: 0.25))
            } else if equity > 0.12 {
                return ("BORDERLINE", "Slight edge — doubling is marginal here",
                        Color(red: 0.95, green: 0.80, blue: 0.10))
            } else if equity > -0.20 {
                return ("NO DOUBLE", "Game is close — hold the cube for now",
                        PC.cream.opacity(0.50))
            } else {
                return ("BEWARE", "You'd be at a disadvantage — watch for a double from your opponent",
                        Color(red: 0.80, green: 0.25, blue: 0.15))
            }
        }()
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.55), lineWidth: 1))
                        .frame(width: 22, height: 22)
                    Text("2×")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(color)
                    .kerning(1)
            }
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PC.cream.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.65))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.30), lineWidth: 1))
        )
    }

    @ViewBuilder
    private func analysisBanner(analysis: MoveAnalysis) -> some View {
        let rendered = ExplanationRenderer.render(analysis)
        let tint = severityColor(analysis.severity)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                Text(rendered.headline)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PC.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let eq = analysis.playerEquity
            if eq > 0.35 {
                let cubeText = eq > 0.75 ? "Too good to double — play for gammon" : "Consider offering the doubling cube"
                HStack(spacing: 4) {
                    Text("2×")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.25))
                    Text(cubeText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(PC.cream.opacity(0.65))
                }
            } else if eq < -0.20 {
                HStack(spacing: 4) {
                    Text("2×")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.80, green: 0.25, blue: 0.15))
                    Text("You'd be at a disadvantage — watch for a double next turn")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(PC.cream.opacity(0.65))
                }
            }
            if analysis.severity != .fine && !rendered.details.isEmpty {
                Button("EXPLAIN WHY?") {
                    presentedAnalysis = AnalysisPresentation(analysis: analysis)
                }
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .kerning(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.30))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(0.40), lineWidth: 1))
        )
    }

    private func dieSelector(value: Binding<Int>) -> some View {
        HStack(spacing: 0) {
            Button { value.wrappedValue = max(1, value.wrappedValue - 1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            Text("\(value.wrappedValue)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .frame(width: 28)
            Button { value.wrappedValue = min(6, value.wrappedValue + 1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
            }
        }
        .foregroundStyle(PC.cream)
        .background(RoundedRectangle(cornerRadius: 6).fill(PC.bg.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(PC.cream.opacity(0.20), lineWidth: 1)))
    }

    private func setupColorButton(_ color: Player, label: String) -> some View {
        let isSelected = vm.setupColor == color
        let isWhite    = color == .white
        return Button(label) { vm.setupColor = color }
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(isWhite ? Color(red: 0.17, green: 0.09, blue: 0.03) : PC.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isWhite ? Color(white: 0.90) : Color(white: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? PC.cream.opacity(0.65) : Color.clear, lineWidth: 1.5)
            )
    }
}

// MARK: - Severity colour

private func severityColor(_ severity: ErrorSeverity) -> Color {
    switch severity {
    case .fine:       return Color(red: 0.20, green: 0.70, blue: 0.25)
    case .inaccuracy: return Color(red: 0.95, green: 0.80, blue: 0.10)
    case .error:      return Color(red: 0.90, green: 0.45, blue: 0.10)
    case .blunder:    return Color(red: 0.75, green: 0.10, blue: 0.10)
    }
}

// MARK: - Explanation sheet

private struct ExplanationSheet: View {
    let analysis: MoveAnalysis
    @Environment(\.dismiss) private var dismiss
    @State private var altIndex = 0
    @State private var oppIndex = 0

    private var rendered: RenderedExplanation { ExplanationRenderer.render(analysis) }
    private var tint: Color { severityColor(analysis.severity) }

    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.07, blue: 0.02).ignoresSafeArea()
            VStack(spacing: 0) {
                // Fixed header
                HStack(spacing: 10) {
                    Image(systemName: severitySymbol(analysis.severity))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(tint)
                    Text("COACH FEEDBACK")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(PC.cream)
                        .kerning(2)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(PC.dim)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Rectangle().fill(PC.cream.opacity(0.10)).frame(height: 1)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {

                        // SECTION 1: Summary + reasons
                        VStack(alignment: .leading, spacing: 12) {
                            sheetSectionHeader("SUMMARY")
                            Text(rendered.headline)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                            if !rendered.details.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(rendered.details.indices, id: \.self) { i in
                                        HStack(alignment: .top, spacing: 10) {
                                            Circle()
                                                .fill(PC.dim)
                                                .frame(width: 5, height: 5)
                                                .padding(.top, 6)
                                            Text(rendered.details[i])
                                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                                .foregroundStyle(PC.cream.opacity(0.85))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }

                        // SECTION 2: Cube advice
                        VStack(alignment: .leading, spacing: 10) {
                            sheetSectionHeader("CUBE ADVICE")
                            cubeAdviceSection
                        }

                        // SECTION 3: Shot risk
                        VStack(alignment: .leading, spacing: 10) {
                            sheetSectionHeader("SHOT RISK")
                            shotRiskSection
                        }

                        // SECTION 3: Opponent's possible responses
                        if !analysis.topOpponentResponses.isEmpty {
                            let oppResps = analysis.topOpponentResponses
                            let curResp  = oppResps[min(oppIndex, oppResps.count - 1)]
                            VStack(alignment: .leading, spacing: 10) {
                                sheetSectionHeader("OPPONENT'S POSSIBLE RESPONSES")
                                if let (d1, d2) = curResp.dice {
                                    Text("If they roll \(d1)-\(d2), here's what they can do:")
                                        .font(.system(size: 13, weight: .regular, design: .rounded))
                                        .foregroundStyle(PC.cream.opacity(0.60))
                                }
                                AnimatedMoveView(
                                    fromState: analysis.playerFinalState,
                                    toState: curResp.finalState,
                                    move: curResp.move,
                                    player: .black
                                )
                                .id(oppIndex)
                                .frame(width: 480, height: 276)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .frame(maxWidth: .infinity)
                                if oppResps.count > 1 {
                                    HStack(spacing: 10) {
                                        Spacer()
                                        Button {
                                            oppIndex = (oppIndex + 1) % oppResps.count
                                        } label: {
                                            Label("Show me another", systemImage: "arrow.counterclockwise")
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundStyle(PC.cream)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Color.white.opacity(0.08))
                                                .clipShape(Capsule())
                                        }
                                        Text("\(oppIndex + 1) of \(oppResps.count)")
                                            .font(.system(size: 12, weight: .regular, design: .rounded))
                                            .foregroundStyle(PC.cream.opacity(0.50))
                                        Spacer()
                                    }
                                }
                            }
                        }

                        // SECTION 4: Better alternative
                        VStack(alignment: .leading, spacing: 10) {
                            sheetSectionHeader("BETTER ALTERNATIVE")
                            Text("Here's what you could have played:")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(PC.cream.opacity(0.60))
                            let alts = analysis.topAlternatives
                            let curAlt = alts.isEmpty ? nil : alts[min(altIndex, alts.count - 1)]
                            let altShots = MoveExplainer.countHittingRolls(against: curAlt?.finalState ?? analysis.bestFinalState)
                            let specificReasons = specificAltReasons(
                                preTurnState: analysis.preTurnState,
                                playerState: analysis.playerFinalState,
                                altState: curAlt?.finalState ?? analysis.bestFinalState,
                                playerShots: analysis.playerShotsAgainstBlots,
                                altShots: altShots
                            )
                            HStack(alignment: .top, spacing: 14) {
                                AnimatedMoveView(
                                    fromState: analysis.preTurnState,
                                    toState: curAlt?.finalState ?? analysis.bestFinalState,
                                    move: curAlt?.move ?? analysis.bestMove,
                                    player: .white
                                )
                                .id(altIndex)
                                .frame(width: 480, height: 276)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(specificReasons.enumerated()), id: \.offset) { _, text in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color(red: 0.25, green: 0.75, blue: 0.30))
                                                .padding(.top, 1)
                                            Text(text)
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundStyle(PC.cream.opacity(0.85))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            if alts.count > 1 {
                                HStack(spacing: 10) {
                                    Spacer()
                                    Button {
                                        altIndex = (altIndex + 1) % alts.count
                                    } label: {
                                        Label("Show me another", systemImage: "arrow.counterclockwise")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(PC.cream)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(Color.white.opacity(0.08))
                                            .clipShape(Capsule())
                                    }
                                    Text("\(altIndex + 1) of \(alts.count)")
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundStyle(PC.cream.opacity(0.50))
                                    Spacer()
                                }
                            }
                        }

                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(red: 0.12, green: 0.07, blue: 0.02))
        .presentationCornerRadius(16)
        .preferredColorScheme(.dark)
    }

    // MARK: Probability table

    private var cubeAdviceSection: some View {
        let eq = analysis.playerEquity
        let (label, title, detail, color): (String, String, String, Color) = {
            if eq > 0.75 {
                return ("TOO GOOD",
                        "Too good to double right now",
                        "You're likely winning a gammon. Doubling would let your opponent off cheap — keep the pressure on.",
                        Color(red: 0.20, green: 0.70, blue: 0.25))
            } else if eq > 0.35 {
                return ("DOUBLE",
                        "Consider offering the doubling cube",
                        "You have a clear advantage. Doubling now forces your opponent to make a tough take-or-drop decision.",
                        Color(red: 0.20, green: 0.70, blue: 0.25))
            } else if eq > 0.12 {
                return ("BORDERLINE",
                        "Double is marginal here",
                        "Slight edge, but not enough to double efficiently. Wait for a more decisive advantage before offering the cube.",
                        Color(red: 0.95, green: 0.80, blue: 0.10))
            } else if eq > -0.20 {
                return ("NO DOUBLE",
                        "Hold the cube — game is close",
                        "The position is roughly even. A double here would be premature; your opponent can easily take.",
                        PC.cream.opacity(0.55))
            } else {
                return ("BEWARE",
                        "You're behind — expect a double",
                        "Your opponent has the advantage. Be ready to decide whether to take or pass if they offer the cube.",
                        Color(red: 0.80, green: 0.25, blue: 0.15))
            }
        }()
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.20))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.50), lineWidth: 1))
                    .frame(width: 40, height: 40)
                VStack(spacing: 0) {
                    Text("2×")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(color)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(color)
                    .kerning(1)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PC.cream)
                Text(detail)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(PC.cream.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shotRiskSection: some View {
        let ps   = analysis.playerShotsAgainstBlots
        let bs   = analysis.bestShotsAgainstBlots
        let playerBlots = (1...24).filter { analysis.playerFinalState.points[$0] == 1 }
        let bestBlots   = (1...24).filter { analysis.bestFinalState.points[$0] == 1 }

        return VStack(alignment: .leading, spacing: 12) {
            if playerBlots.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.25, green: 0.75, blue: 0.30))
                    Text("No exposed checkers after your move.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(PC.cream.opacity(0.85))
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(ps)")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(shotColor(ps))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("of 36 rolls can hit you")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(PC.cream.opacity(0.70))
                        Text("\(Int(round(Float(ps) / 36.0 * 100)))% chance of being hit")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(shotColor(ps).opacity(0.80))
                    }
                }
                HStack(spacing: 6) {
                    Text("Exposed on:")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(PC.cream.opacity(0.45))
                    ForEach(playerBlots, id: \.self) { p in
                        Text("pt \(p)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(PC.cream.opacity(0.85))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }

            Rectangle().fill(PC.cream.opacity(0.08)).frame(height: 1)

            HStack(spacing: 8) {
                if bestBlots.isEmpty || bs < ps {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(Color(red: 0.25, green: 0.75, blue: 0.30))
                    if bestBlots.isEmpty {
                        Text("The better move leaves no blots exposed.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PC.cream.opacity(0.70))
                    } else {
                        Text("The better move: only \(bs) of 36 rolls can hit (\(Int(round(Float(bs) / 36.0 * 100)))%).")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PC.cream.opacity(0.70))
                    }
                } else {
                    Image(systemName: "info.circle")
                        .foregroundStyle(PC.cream.opacity(0.45))
                    Text("The better move is stronger for positional reasons, not shot safety.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PC.cream.opacity(0.60))
                }
            }

            Rectangle().fill(PC.cream.opacity(0.08)).frame(height: 1)

            // Zone breakdown
            VStack(alignment: .leading, spacing: 0) {
                Text("BY ZONE")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(PC.cream.opacity(0.35))
                    .kerning(1)
                    .padding(.bottom, 8)

                let zones: [(String, ClosedRange<Int>)] = [
                    ("Black's Home", 19...24),
                    ("Black's Outer", 13...18),
                    ("White's Outer", 7...12),
                    ("White's Home", 1...6)
                ]
                ForEach(0..<4, id: \.self) { i in
                    let (name, range) = zones[i]
                    let zoneBlots = range.filter { analysis.playerFinalState.points[$0] == 1 }
                    let zoneShots = analysis.playerShotsByZone.count > i ? analysis.playerShotsByZone[i] : 0
                    let pct = Int(round(Float(zoneShots) / 36.0 * 100))
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(PC.cream.opacity(0.80))
                            if zoneBlots.isEmpty {
                                Text("No blots")
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundStyle(PC.cream.opacity(0.30))
                            } else {
                                HStack(spacing: 4) {
                                    ForEach(zoneBlots, id: \.self) { p in
                                        Text("pt \(p)")
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .foregroundStyle(PC.cream.opacity(0.70))
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Color.white.opacity(0.07))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        Spacer()
                        if zoneShots == 0 {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(red: 0.25, green: 0.75, blue: 0.30))
                        } else {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(zoneShots)/36")
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundStyle(shotColor(zoneShots))
                                Text("\(pct)%")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(shotColor(zoneShots).opacity(0.75))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    if i < 3 {
                        Rectangle().fill(PC.cream.opacity(0.06)).frame(height: 1)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(PC.cream.opacity(0.08), lineWidth: 1))
    }

    private func shotColor(_ shots: Int) -> Color {
        switch shots {
        case 0:      return Color(red: 0.25, green: 0.75, blue: 0.30)
        case 1...8:  return PC.cream
        case 9...18: return Color(red: 0.85, green: 0.65, blue: 0.10)
        default:     return Color(red: 0.80, green: 0.25, blue: 0.20)
        }
    }

    // MARK: Helpers

    private func sheetSectionHeader(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(PC.dim).kerning(2)
            Rectangle().fill(PC.cream.opacity(0.10)).frame(height: 1)
        }
    }
    private func specificAltReasons(
        preTurnState: BoardState,
        playerState: BoardState,
        altState: BoardState,
        playerShots: Int,
        altShots: Int
    ) -> [String] {
        var out: [String] = []

        // Missed hit: alternative hits a black blot the player left alone
        for p in 1...24 where out.count < 3 {
            if preTurnState.points[p] == -1 && playerState.points[p] == -1 && altState.points[p] == 1 {
                out.append("You left the black blot on point \(p) alone — this hits it and sends it to the bar")
            }
        }

        // Blot safety: player created blots that this move avoids
        let playerBlots = (1...24).filter { playerState.points[$0] == 1 }
        let altBlots    = (1...24).filter { altState.points[$0] == 1 }
        let avoided = playerBlots.filter { !altBlots.contains($0) }
        if !avoided.isEmpty && out.count < 3 {
            if avoided.count == 1 {
                out.append("Your move left a blot on point \(avoided[0]) — this move keeps that checker safe")
            } else {
                out.append("Your move left blots on points \(avoided.map(String.init).joined(separator: ", ")) — this avoids all of them")
            }
        }

        // Shot reduction (only if meaningful difference)
        if altShots < playerShots && playerShots - altShots >= 4 && out.count < 3 {
            out.append("Cuts your exposure from \(playerShots) to \(altShots) of 36 possible shots")
        }

        // Point making: alternative secures a point the player's move didn't
        for p in 1...24 where out.count < 3 {
            if altState.points[p] >= 2 && playerState.points[p] < 2 && preTurnState.points[p] < 2 {
                let key = [3, 4, 5, 7, 18, 20].contains(p)
                out.append(key ? "Makes the key point on \(p), which your move missed"
                               : "Builds a made point on \(p) — your move left it open")
                break
            }
        }

        // Stacking: player piled checkers on one point unnecessarily
        for p in 1...24 where out.count < 3 {
            let pc = playerState.points[p], ac = altState.points[p]
            if pc >= 4 && ac < pc && ac > 0 {
                out.append("Your move stacked \(pc) checkers on point \(p) — this spreads them more usefully")
                break
            }
        }

        // Forward blot: alternative's new blot is deep in black's territory (≥18).
        // White re-enters from the bar at points 19–24, so a blot there costs almost
        // nothing if hit — whereas a blot near your own home costs 14–18 pips.
        let altNewBlots = altBlots.filter { preTurnState.points[$0] != 1 }
        let altDeepBlots = altNewBlots.filter { $0 >= 18 }
        if !altDeepBlots.isEmpty && out.count < 4 {
            let p = altDeepBlots.max()!
            let location = p >= 19 ? "inside black's home board" : "deep in black's territory"
            if let q = playerBlots.filter({ $0 < 18 }).min() {
                out.append("Your blot on point \(q) would cost ~\(21 - q) pips if hit — this blot \(location) (point \(p)) re-enters almost in place")
            } else {
                out.append("Leaving a blot \(location) (point \(p)) is low risk — if hit, you re-enter just a few points away")
            }
        }

        if out.isEmpty { out.append("Achieves a stronger overall position by the numbers") }
        return out
    }

    private func severitySymbol(_ severity: ErrorSeverity) -> String {
        switch severity {
        case .fine:       return "checkmark.circle.fill"
        case .inaccuracy: return "exclamationmark.circle"
        case .error:      return "exclamationmark.triangle"
        case .blunder:    return "xmark.octagon.fill"
        }
    }
}

// MARK: - Static board snapshot (read-only, exact visual match of the main board)

private struct StaticBoardView: View {
    let state: BoardState
    var highlights: Set<Int> = []
    var hiddenPoint: Int? = nil   // hides the top checker (it's in flight)

    var body: some View {
        GeometryReader { geo in
            // Same layout math as the main board
            let W    = geo.size.width
            let H    = geo.size.height
            let barW = max(H * 0.065, 20)
            let ptW  = (W - barW) / 12
            let ptH  = (H - 20) / 2
            let cSz  = min(ptW * 0.84, ptH / 4.6)

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.42, green: 0.24, blue: 0.10))
                HStack(spacing: 0) {
                    staticHalf(topPts: [13,14,15,16,17,18], botPts: [12,11,10,9,8,7],
                               ptW: ptW, ptH: ptH, cSz: cSz)
                    staticBarPanel(barW: barW, ptH: ptH, cSz: cSz)
                    staticHalf(topPts: [19,20,21,22,23,24], botPts: [6,5,4,3,2,1],
                               ptW: ptW, ptH: ptH, cSz: cSz)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
    }

    private func staticHalf(topPts: [Int], botPts: [Int], ptW: CGFloat, ptH: CGFloat, cSz: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(topPts, id: \.self) { p in
                    staticPoint(p, isTop: true,  ptW: ptW, ptH: ptH, cSz: cSz)
                }
            }
            Spacer(minLength: 20)
            HStack(spacing: 0) {
                ForEach(botPts, id: \.self) { p in
                    staticPoint(p, isTop: false, ptW: ptW, ptH: ptH, cSz: cSz)
                }
            }
        }
        .frame(width: ptW * 6)
    }

    @ViewBuilder
    private func staticPoint(_ p: Int, isTop: Bool, ptW: CGFloat, ptH: CGFloat, cSz: CGFloat) -> some View {
        let raw     = state.points[p]
        let n       = max(0, abs(raw) - (p == hiddenPoint ? 1 : 0))
        let isWhite = raw > 0
        let lit     = highlights.contains(p)
        let triColor: Color = p % 2 == 0
            ? Color(red: 0.62, green: 0.08, blue: 0.06)
            : Color(red: 0.94, green: 0.87, blue: 0.68)

        ZStack(alignment: isTop ? .top : .bottom) {
            PointTriangle(down: isTop).fill(triColor)
            if lit { PointTriangle(down: isTop).fill(Color.yellow.opacity(0.32)) }
            if n > 0 {
                let show  = min(n, 5)
                let step: CGFloat = show > 1 ? min(cSz * 0.72, (ptH - cSz) / CGFloat(show - 1)) : cSz
                VStack(spacing: step - cSz) {
                    if isTop {
                        ForEach(0..<show, id: \.self) { _ in staticDisc(isWhite: isWhite, cSz: cSz) }
                        if n > 5 { Text("+\(n-5)").font(.caption2.bold()).foregroundStyle(.white) }
                        Spacer(minLength: 0)
                    } else {
                        Spacer(minLength: 0)
                        if n > 5 { Text("+\(n-5)").font(.caption2.bold()).foregroundStyle(.white) }
                        ForEach(0..<show, id: \.self) { _ in staticDisc(isWhite: isWhite, cSz: cSz) }
                    }
                }
            }
        }
        .frame(width: ptW, height: ptH)
    }

    private func staticBarPanel(barW: CGFloat, ptH: CGFloat, cSz: CGFloat) -> some View {
        VStack {
            staticBarSection(.black, barW: barW, cSz: cSz)
            Spacer()
            staticBarSection(.white, barW: barW, cSz: cSz)
        }
        .padding(.vertical, 6)
        .frame(width: barW, height: ptH * 2 + 20)
        .background(Color(red: 0.26, green: 0.14, blue: 0.05))
    }

    @ViewBuilder
    private func staticBarSection(_ player: Player, barW: CGFloat, cSz: CGFloat) -> some View {
        let count = player == .white ? state.whiteBar : state.blackBar
        let sz    = min(barW * 0.78, cSz)
        if count > 0 {
            VStack(spacing: 2) {
                ForEach(0..<min(count, 3), id: \.self) { _ in
                    staticDisc(isWhite: player == .white, cSz: sz)
                }
                if count > 3 { Text("+\(count-3)").font(.caption2.bold()).foregroundColor(.white) }
            }
            .padding(3)
        }
    }

    // Exact match of checkerDisc in PointView — radial gradient + stroke + specular ellipse + shadow
    private func staticDisc(isWhite: Bool, cSz: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [
                        isWhite ? Color(white: 1.0) : Color(white: 0.42),
                        isWhite ? Color(white: 0.68) : Color(white: 0.07)
                    ],
                    center: UnitPoint(x: 0.33, y: 0.28),
                    startRadius: 0,
                    endRadius: cSz * 0.58
                ))
            Circle()
                .stroke(isWhite ? Color(white: 0.52) : Color(white: 0.58), lineWidth: 1.5)
            Ellipse()
                .fill(Color.white.opacity(isWhite ? 0.70 : 0.25))
                .frame(width: cSz * 0.36, height: cSz * 0.20)
                .offset(x: -cSz * 0.09, y: -cSz * 0.17)
        }
        .frame(width: cSz, height: cSz)
        .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0.5, y: 1)
    }
}

// MARK: - Board layout helpers for mini-board flying animation

private struct BoardLayout {
    let W: CGFloat, H: CGFloat, barW: CGFloat, ptW: CGFloat, ptH: CGFloat, cSz: CGFloat
    var boardH: CGFloat { ptH * 2 + 20 }
    var key: String { "\(Int(W))x\(Int(H))" }

    init(_ size: CGSize) {
        W = size.width; H = size.height
        barW = max(H * 0.065, 20)
        ptW  = (W - barW) / 12
        ptH  = (H - 20) / 2
        cSz  = min(ptW * 0.84, ptH / 4.6)
    }

    func ptX(_ p: Int) -> CGFloat {
        switch p {
        case 13...18: return CGFloat(p - 13) * ptW + ptW / 2
        case 19...24: return ptW * 6 + barW + CGFloat(p - 19) * ptW + ptW / 2
        case 7...12:  return CGFloat(12 - p) * ptW + ptW / 2
        case 1...6:   return ptW * 6 + barW + CGFloat(6 - p) * ptW + ptW / 2
        default:      return W / 2
        }
    }

    func stackTopY(_ p: Int, count: Int) -> CGFloat {
        let n = max(count, 1)
        let step: CGFloat = n > 1 ? min(cSz * 0.72, (ptH - cSz) / CGFloat(n - 1)) : cSz
        let offset = CGFloat(n - 1) * step
        return (13...24).contains(p) ? cSz / 2 + offset : boardH - cSz / 2 - offset
    }

    func srcCenter(_ from: Int, state: BoardState) -> CGPoint {
        switch from {
        case 25: return CGPoint(x: ptW * 6 + barW / 2, y: boardH - cSz * 2)
        case 0:  return CGPoint(x: ptW * 6 + barW / 2, y: cSz * 2)
        default:
            return CGPoint(x: ptX(from), y: stackTopY(from, count: abs(state.points[from])))
        }
    }

    func dstCenter(_ to: Int, state: BoardState) -> CGPoint {
        switch to {
        case 0:  return CGPoint(x: W + cSz, y: boardH * 0.75)
        case 25: return CGPoint(x: W + cSz, y: boardH * 0.25)
        default:
            return CGPoint(x: ptX(to), y: stackTopY(to, count: abs(state.points[to])))
        }
    }
}

// MARK: - Animated move view (flying-checker animation)

private struct AnimatedMoveView: View {
    let fromState: BoardState
    let toState: BoardState
    var move: Move = []
    var player: Player = .white

    @State private var displayState: BoardState
    @State private var dispHighlights: Set<Int> = []
    @State private var hiddenPoint: Int? = nil
    @State private var flyVisible = false
    @State private var flyPos: CGPoint = .zero
    @State private var flyIsWhite = true

    init(fromState: BoardState, toState: BoardState, move: Move = [], player: Player = .white) {
        self.fromState = fromState; self.toState = toState
        self.move = move; self.player = player
        _displayState = State(initialValue: fromState)
    }

    // Infer per-checker steps from state diff when no move sequence is provided.
    // Uses player-specific checker counts to handle hit checkers correctly.
    private var effectiveSteps: [CheckerMove] {
        if !move.isEmpty { return move }
        var sources = [Int](), dests = [Int]()
        for p in 1...24 {
            let fc = player == .white ? max(0,  fromState.points[p]) : max(0, -fromState.points[p])
            let tc = player == .white ? max(0,  toState.points[p])   : max(0, -toState.points[p])
            if fc > tc { for _ in 0..<(fc - tc) { sources.append(p) } }
            if tc > fc { for _ in 0..<(tc - fc) { dests.append(p)   } }
        }
        if player == .white, fromState.whiteBar > toState.whiteBar {
            for _ in 0..<(fromState.whiteBar - toState.whiteBar) { sources.append(25) }
        }
        if player == .black, fromState.blackBar > toState.blackBar {
            for _ in 0..<(fromState.blackBar - toState.blackBar) { sources.append(0) }
        }
        if player == .white, toState.whiteBorneOff > fromState.whiteBorneOff {
            for _ in 0..<(toState.whiteBorneOff - fromState.whiteBorneOff) { dests.append(0) }
        }
        if player == .black, toState.blackBorneOff > fromState.blackBorneOff {
            for _ in 0..<(toState.blackBorneOff - fromState.blackBorneOff) { dests.append(25) }
        }
        return zip(sources, dests).map { src, dst in
            CheckerMove(from: src, to: dst, die: abs(dst - src))
        }
    }

    private var srcHighlights: Set<Int> {
        Set(effectiveSteps.compactMap { (1...24).contains($0.from) ? $0.from : nil })
    }
    private var dstHighlights: Set<Int> {
        Set(effectiveSteps.compactMap { (1...24).contains($0.to) ? $0.to : nil })
    }

    var body: some View {
        GeometryReader { geo in
            let layout = BoardLayout(geo.size)
            ZStack {
                StaticBoardView(state: displayState, highlights: dispHighlights, hiddenPoint: hiddenPoint)
                if flyVisible {
                    flyDisc(isWhite: flyIsWhite, cSz: layout.cSz)
                        .position(flyPos)
                        .allowsHitTesting(false)
                }
            }
            .task(id: layout.key) {
                await runLoop(layout: layout)
            }
        }
    }

    private func runLoop(layout: BoardLayout) async {
        let steps = effectiveSteps
        while !Task.isCancelled {
            displayState   = fromState
            dispHighlights = srcHighlights
            hiddenPoint    = nil
            flyVisible     = false
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }

            var cur = fromState
            for step in steps {
                let src = layout.srcCenter(step.from, state: cur)
                var moverState = cur
                moverState.currentPlayer = player   // applying() uses this to pick the right color
                let nxt = moverState.applying(step)
                let dst = layout.dstCenter(step.to, state: nxt)

                hiddenPoint    = (1...24).contains(step.from) ? step.from : nil
                flyIsWhite     = player == .white
                flyPos         = src
                flyVisible     = true
                dispHighlights = []

                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.42)) { flyPos = dst }
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }

                flyVisible   = false
                hiddenPoint  = nil
                displayState = nxt
                cur          = nxt
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
            }

            displayState   = toState
            dispHighlights = dstHighlights
            hiddenPoint    = nil
            flyVisible     = false
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
        }
    }

    private func flyDisc(isWhite: Bool, cSz: CGFloat) -> some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [isWhite ? Color(white: 1.0) : Color(white: 0.42),
                         isWhite ? Color(white: 0.68) : Color(white: 0.07)],
                center: UnitPoint(x: 0.33, y: 0.28),
                startRadius: 0, endRadius: cSz * 0.58
            ))
            Circle().stroke(isWhite ? Color(white: 0.52) : Color(white: 0.58), lineWidth: 1.5)
            Ellipse()
                .fill(Color.white.opacity(isWhite ? 0.70 : 0.25))
                .frame(width: cSz * 0.36, height: cSz * 0.20)
                .offset(x: -cSz * 0.09, y: -cSz * 0.17)
        }
        .frame(width: cSz * 1.08, height: cSz * 1.08)
        .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 2)
    }
}

// MARK: - PointView

private struct PointView: View {
    let point: Int
    let isTop: Bool
    let ptW: CGFloat
    let ptH: CGFloat
    let barW: CGFloat
    let cSz: CGFloat
    @Environment(GameViewModel.self) private var vm

    private var raw:        Int  { vm.state.points[point] }
    private var isSelected: Bool { vm.selectedPoint == point }
    private var isDest:     Bool { vm.legalDestinations.contains(point) }

    var body: some View {
        ZStack(alignment: isTop ? .top : .bottom) {
            PointTriangle(down: isTop).fill(triColor)
            if isDest     { PointTriangle(down: isTop).fill(Color(red: 0.0, green: 1.0, blue: 0.6).opacity(0.55)) }
            if isSelected { PointTriangle(down: isTop).stroke(Color(red: 1.0, green: 0.85, blue: 0.0), lineWidth: 3) }
            checkerStack
        }
        .frame(width: ptW, height: ptH)
        .contentShape(PointTriangle(down: isTop))
        .gesture(tapOrDragGesture)
    }

    // Single gesture handles both tap and drag to avoid SwiftUI gesture competition.
    // Movement ≤ 12 pt → treated as tap; more → drag.
    private var tapOrDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("board"))
            .onChanged { val in
                let moved = hypot(val.translation.width, val.translation.height)
                guard moved > 12 else { return }
                if vm.dragSource == nil {
                    guard vm.state.barCount(for: vm.state.currentPlayer) == 0 else { return }
                    guard vm.selectableSources.contains(point) else { return }
                    vm.dragSource = point
                    vm.selectedPoint = point
                } else if vm.dragSource != point {
                    return
                }
                vm.dragPosition = val.location
            }
            .onEnded { val in
                let moved = hypot(val.translation.width, val.translation.height)
                if moved <= 12 {
                    vm.clearDragState()   // preserve selectedPoint so two-tap bar entry works
                    vm.tap(point: point)
                    return
                }
                guard vm.dragSource == point else { vm.cancelDrag(); return }
                let boardW = ptW * 12 + barW
                let player = vm.state.currentPlayer
                if val.location.x > boardW && vm.legalDestinations.contains(player.boreOffPoint) {
                    vm.drop(to: player.boreOffPoint)
                } else if let dest = pointAt(val.location), vm.legalDestinations.contains(dest) {
                    vm.drop(to: dest)
                } else {
                    vm.cancelDrag()
                }
            }
    }

    // Map board-space coordinates to a point number (1–24).
    private func pointAt(_ pos: CGPoint) -> Int? {
        let boardH = ptH * 2 + 20
        for p in 1...24 {
            let cx: CGFloat
            switch p {
            case 13...18: cx = CGFloat(p - 13) * ptW + ptW / 2
            case 19...24: cx = ptW * 6 + barW + CGFloat(p - 19) * ptW + ptW / 2
            case 7...12:  cx = CGFloat(12 - p) * ptW + ptW / 2
            case 1...6:   cx = ptW * 6 + barW + CGFloat(6 - p) * ptW + ptW / 2
            default:      continue
            }
            let isTopRow = (13...24).contains(p)
            let yMin: CGFloat = isTopRow ? 0 : ptH + 20
            let yMax: CGFloat = isTopRow ? ptH : boardH
            if abs(pos.x - cx) <= ptW / 2 && pos.y >= yMin && pos.y <= yMax { return p }
        }
        return nil
    }

    private var triColor: Color {
        point % 2 == 0
            ? Color(red: 0.62, green: 0.08, blue: 0.06)   // deep burgundy
            : Color(red: 0.94, green: 0.87, blue: 0.68)   // warm cream
    }

    @ViewBuilder
    private var checkerStack: some View {
        let base = abs(raw)
        let isWhiteChecker = raw > 0
        // Hide arriving checker during flight; hide top checker while it is being dragged.
        let n: Int = {
            if let f = vm.flightInfo, f.to == point, f.isWhite == isWhiteChecker, base > 0 { return base - 1 }
            if vm.dragSource == point && base > 0 { return base - 1 }
            return base
        }()
        if n > 0 {
            let step: CGFloat = n > 1 ? min(cSz * 0.72, (ptH - cSz) / CGFloat(n - 1)) : cSz
            VStack(spacing: step - cSz) {
                if isTop {
                    ForEach(0..<n, id: \.self) { _ in checkerDisc(isWhite: isWhiteChecker) }
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    ForEach(0..<n, id: \.self) { _ in checkerDisc(isWhite: isWhiteChecker) }
                }
            }
        }
    }

    private func checkerDisc(isWhite: Bool) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [
                        isWhite ? Color(white: 1.0) : Color(white: 0.42),
                        isWhite ? Color(white: 0.68) : Color(white: 0.07)
                    ],
                    center: UnitPoint(x: 0.33, y: 0.28),
                    startRadius: 0,
                    endRadius: cSz * 0.58
                ))
            Circle()
                .stroke(isWhite ? Color(white: 0.52) : Color(white: 0.58), lineWidth: 1.5)
            Ellipse()
                .fill(Color.white.opacity(isWhite ? 0.70 : 0.25))
                .frame(width: cSz * 0.36, height: cSz * 0.20)
                .offset(x: -cSz * 0.09, y: -cSz * 0.17)
        }
        .frame(width: cSz, height: cSz)
        .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0.5, y: 1)
    }
}

// MARK: - Shapes & helpers

private struct PointTriangle: Shape {
    var down: Bool
    func path(in rect: CGRect) -> Path {
        Path {
            if down {
                $0.move(to: .init(x: rect.minX, y: rect.minY))
                $0.addLine(to: .init(x: rect.maxX, y: rect.minY))
                $0.addLine(to: .init(x: rect.midX, y: rect.maxY))
            } else {
                $0.move(to: .init(x: rect.minX, y: rect.maxY))
                $0.addLine(to: .init(x: rect.maxX, y: rect.maxY))
                $0.addLine(to: .init(x: rect.midX, y: rect.minY))
            }
            $0.closeSubpath()
        }
    }
}

// MARK: - Checker flight animation overlay

private struct CheckerFlightOverlay: View {
    let ptW: CGFloat, ptH: CGFloat, barW: CGFloat, cSz: CGFloat
    @Environment(GameViewModel.self) private var vm

    @State private var animPos: CGPoint = .zero
    @State private var visible = false
    @State private var isWhite = true
    @State private var flightTask: Task<Void, Never>?

    private var boardH: CGFloat { ptH * 2 + 20 }
    private var boardW: CGFloat { ptW * 12 + barW }

    var body: some View {
        ZStack {
            if visible {
                disc(isWhite: isWhite)
                    .position(animPos)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: boardW, height: boardH)
        .onChange(of: vm.flightInfo) { _, flight in
            guard let flight else { return }
            flightTask?.cancel()
            let src = sourceCenter(for: flight)
            let dst = destCenter(for: flight)
            isWhite = flight.isWhite
            visible = false
            animPos = src
            flightTask = Task {
                // Let the src-position render commit before animating
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                let duration: Double = flight.isAutoPlay ? 0.40 : 0.25
                let holdMs: Int      = flight.isAutoPlay ? 700  : 300
                visible = true
                withAnimation(.easeInOut(duration: duration)) { animPos = dst }
                try? await Task.sleep(for: .milliseconds(holdMs))
                guard !Task.isCancelled else { return }
                visible = false
                vm.flightInfo = nil
            }
        }
    }

    private func sourceCenter(for f: FlightInfo) -> CGPoint {
        switch f.from {
        case 25: return CGPoint(x: ptW * 6 + barW / 2, y: boardH - cSz * 2)  // white bar
        case 0:  return CGPoint(x: ptW * 6 + barW / 2, y: cSz * 2)           // black bar
        default:
            // State already reflects the removal, so original count = current + 1.
            let n = abs(vm.state.points[f.from]) + 1
            return CGPoint(x: ptX(f.from), y: stackTopY(f.from, count: n))
        }
    }

    private func destCenter(for f: FlightInfo) -> CGPoint {
        switch f.to {
        case 0:  return CGPoint(x: boardW + cSz, y: boardH * 0.75)  // white bore-off (off right)
        case 25: return CGPoint(x: boardW + cSz, y: boardH * 0.25)  // black bore-off (off right)
        default:
            // State already reflects the addition, so current count = final count.
            let m = abs(vm.state.points[f.to])
            return CGPoint(x: ptX(f.to), y: stackTopY(f.to, count: m))
        }
    }

    // Y-coordinate of the top checker in a stack of `count` on point `p`.
    private func stackTopY(_ p: Int, count: Int) -> CGFloat {
        let n = max(count, 1)
        let step: CGFloat = n > 1 ? min(cSz * 0.72, (ptH - cSz) / CGFloat(n - 1)) : cSz
        let offset = CGFloat(n - 1) * step
        return (13...24).contains(p) ? cSz / 2 + offset : boardH - cSz / 2 - offset
    }

    private func ptX(_ p: Int) -> CGFloat {
        switch p {
        case 13...18: return CGFloat(p - 13) * ptW + ptW / 2
        case 19...24: return ptW * 6 + barW + CGFloat(p - 19) * ptW + ptW / 2
        case 7...12:  return CGFloat(12 - p) * ptW + ptW / 2
        case 1...6:   return ptW * 6 + barW + CGFloat(6 - p) * ptW + ptW / 2
        default:      return boardW / 2
        }
    }

    private func disc(isWhite: Bool) -> some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [isWhite ? Color(white: 1.0) : Color(white: 0.42),
                         isWhite ? Color(white: 0.68) : Color(white: 0.07)],
                center: UnitPoint(x: 0.33, y: 0.28),
                startRadius: 0, endRadius: cSz * 0.58
            ))
            Circle().stroke(isWhite ? Color(white: 0.52) : Color(white: 0.58), lineWidth: 1.5)
            Ellipse()
                .fill(Color.white.opacity(isWhite ? 0.70 : 0.25))
                .frame(width: cSz * 0.36, height: cSz * 0.20)
                .offset(x: -cSz * 0.09, y: -cSz * 0.17)
        }
        .frame(width: cSz, height: cSz)
        .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Dice face view

private struct DiceFaceView: View {
    let value: Int
    var size: CGFloat = 44

    // Dot offsets as fractions of size, relative to face centre.
    private static let dots: [[(CGFloat, CGFloat)]] = [
        [],
        [(0, 0)],
        [(0.22, -0.22), (-0.22, 0.22)],
        [(0.22, -0.22), (0, 0), (-0.22, 0.22)],
        [(-0.22, -0.22), (0.22, -0.22), (-0.22, 0.22), (0.22, 0.22)],
        [(-0.22, -0.22), (0.22, -0.22), (0, 0), (-0.22, 0.22), (0.22, 0.22)],
        [(-0.22, -0.22), (0.22, -0.22), (-0.22, 0), (0.22, 0), (-0.22, 0.22), (0.22, 0.22)],
    ]

    var body: some View {
        let depth: CGFloat = size * 0.10
        let r:     CGFloat = size * 0.16

        ZStack(alignment: .topLeading) {
            // Visible side faces (bottom-right offset gives cube illusion)
            RoundedRectangle(cornerRadius: r)
                .fill(Color(white: 0.42))
                .frame(width: size, height: size)
                .offset(x: depth, y: depth)

            // Top face — gradient bright top-left → slightly warm bottom-right
            RoundedRectangle(cornerRadius: r)
                .fill(LinearGradient(
                    colors: [Color(white: 0.98), Color(white: 0.90)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: r)
                    .stroke(Color(white: 0.60), lineWidth: 1))
                .overlay(
                    // Dots centred on the face
                    ZStack {
                        if value >= 1, value <= 6 {
                            ForEach(DiceFaceView.dots[value].indices, id: \.self) { i in
                                let (dx, dy) = DiceFaceView.dots[value][i]
                                Circle()
                                    .fill(Color(white: 0.08))
                                    .frame(width: size * 0.16, height: size * 0.16)
                                    .offset(x: dx * size, y: dy * size)
                            }
                        }
                    }
                )
        }
        .frame(width: size + depth, height: size + depth)
        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Settings sheet

private struct SettingsView: View {
    @Environment(GameViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var vm = vm
        ZStack {
            Color(red: 0.12, green: 0.07, blue: 0.02).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(PC.cream)
                    Text("SETTINGS")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(PC.cream)
                        .kerning(2)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(PC.dim)
                    }
                }
                .padding(.bottom, 20)

                Rectangle().fill(PC.cream.opacity(0.10)).frame(height: 1)
                    .padding(.bottom, 4)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {

                // PROFESSIONAL RULES section
                Text("PROFESSIONAL RULES")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(PC.dim)
                    .kerning(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ADVANCED MODE")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(PC.cream)
                            .kerning(1.5)
                        Text("Enables 3-point backgammon endings and the doubling cube")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PC.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $vm.advancedMode)
                        .tint(PC.green)
                        .labelsHidden()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(PC.cream.opacity(0.08), lineWidth: 1))
                )

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PROFESSIONAL TIMER")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(PC.cream)
                            .kerning(1.5)
                        Text("12 seconds per turn — any extra time is deducted from your 10-minute game clock")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PC.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $vm.professionalTimerEnabled)
                        .tint(PC.green)
                        .labelsHidden()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(PC.cream.opacity(0.08), lineWidth: 1))
                )

                // Street Rules section
                Text("STREET RULES")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(PC.dim)
                    .kerning(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("HIT & RUN NOT ALLOWED")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(PC.cream)
                            .kerning(1.5)
                        Text("In your home board, you cannot hit a blot and leave the point empty — your checker must stay (or be covered by another)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PC.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $vm.vurKacRuleEnabled)
                        .tint(PC.brown)
                        .labelsHidden()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(PC.cream.opacity(0.08), lineWidth: 1))
                )

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PLAY OPENING DICE FIRST")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(PC.cream)
                            .kerning(1.5)
                        Text("The two dice rolled to decide who starts must be used as that player's first move")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PC.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $vm.openingDiceAsFirst)
                        .tint(PC.brown)
                        .labelsHidden()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(PC.cream.opacity(0.08), lineWidth: 1))
                )

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("REGULAR TIMER")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(PC.cream)
                            .kerning(1.5)
                        Text("12 seconds per turn — turn ends automatically when time runs out")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PC.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $vm.regularTimerEnabled)
                        .tint(PC.brown)
                        .labelsHidden()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(PC.cream.opacity(0.08), lineWidth: 1))
                )

                // COACH SETTINGS section
                Text("COACH SETTINGS")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(PC.dim)
                    .kerning(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("COACH MODE")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(PC.cream)
                            .kerning(1.5)
                        Text("After each turn, shows how the computer evaluates your move and explains mistakes")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PC.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $vm.coachMode)
                        .tint(PC.green)
                        .labelsHidden()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(PC.cream.opacity(0.08), lineWidth: 1))
                )

                    } // VStack inside ScrollView
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                } // ScrollView
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(red: 0.12, green: 0.07, blue: 0.02))
        .presentationCornerRadius(16)
        .preferredColorScheme(.dark)
    }
}
