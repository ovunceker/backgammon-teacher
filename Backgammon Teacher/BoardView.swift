import SwiftUI

// Top row (L→R): 13–18 | BAR | 19–24    Bottom row (L→R): 12–7 | BAR | 6–1
private let topLeft  = [13, 14, 15, 16, 17, 18]; private let topRight = [19, 20, 21, 22, 23, 24]
private let botLeft  = [12, 11, 10,  9,  8,  7]; private let botRight = [ 6,  5,  4,  3,  2,  1]

// MARK: - BoardView

struct BoardView: View {
    @Environment(GameViewModel.self) private var vm

    @State private var diceDisplayValues: [Int] = []
    @State private var diceRolling = false
    @State private var diceAnimTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            // Landscape: board fills the height; controls live in a right-side panel.
            let panelW: CGFloat = 148
            let pad:    CGFloat = 8
            let boardH  = geo.size.height - pad * 2
            let barW    = max(boardH * 0.065, 20)
            let boardW  = geo.size.width  - panelW - barW - pad * 3
            let ptH     = (boardH - 20) / 2
            let ptW     = (boardW - barW) / 12
            let cSz     = min(ptW * 0.84, ptH / 4.6)

            HStack(alignment: .center, spacing: 0) {
                boardCanvas(W: boardW, ptW: ptW, ptH: ptH, barW: barW, cSz: cSz)
                boreOffTray(trayW: barW, ptH: ptH, cSz: cSz)
                controlPanel
                    .frame(width: panelW)
                    .padding(.leading, pad)
            }
            .padding(pad)
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
    }

    // MARK: Board

    private func boardCanvas(W: CGFloat, ptW: CGFloat, ptH: CGFloat, barW: CGFloat, cSz: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.42, green: 0.24, blue: 0.10))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            HStack(spacing: 0) {
                halfPanel(top: topLeft, bot: botLeft, ptW: ptW, ptH: ptH, barW: barW, cSz: cSz)
                barPanel(barW: barW, ptW: ptW, ptH: ptH, cSz: cSz)
                halfPanel(top: topRight, bot: botRight, ptW: ptW, ptH: ptH, barW: barW, cSz: cSz)
            }
            if vm.dice != nil {
                boardOverlay(ptW: ptW, barW: barW)
            }
            CheckerFlightOverlay(ptW: ptW, ptH: ptH, barW: barW, cSz: cSz)
            // Dragged checker floating overlay
            if let pos = vm.dragPosition {
                dragDisc(isWhite: vm.state.currentPlayer == .white, cSz: cSz)
                    .position(pos)
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
                        vm.cancelDrag()
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
        let isWhite = vm.state.currentPlayer == .white
        let dSz: CGFloat = min(ptW * 0.74, 40)
        let xOff = ptW * 3 + barW / 2

        return VStack(spacing: 10) {
            if let d = vm.dice, !d.remaining.isEmpty {
                let displayVals = diceRolling ? diceDisplayValues : d.remaining
                diceContent(values: displayVals.isEmpty ? d.remaining : displayVals, dSz: dSz)
            }
            if vm.canUndo || vm.pendingEndTurn {
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
        VStack(spacing: 14) {
            if vm.isSetupMode {
                Text("Board Setup")
                    .font(.caption.bold().uppercaseSmallCaps())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    setupColorButton(.white, label: "White")
                    setupColorButton(.black, label: "Black")
                }

                Text("Tap a point to add a checker.\nTap at max (15) or\nopponent to clear.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Clear Board") { vm.clearSetupBoard() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Divider()

                Text("Start game as:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("White starts") { vm.startFromSetup(as: .white) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                Button("Black starts") { vm.startFromSetup(as: .black) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(white: 0.18))
                    .frame(maxWidth: .infinity)

            } else if let w = vm.state.winner {
                Text("\(w == .white ? "White" : "Black") wins!")
                    .font(.headline.bold())
                    .multilineTextAlignment(.center)
                HStack(spacing: 4) {
                    Text("White").foregroundStyle(Color(white: 0.92))
                    Text("\(vm.whiteScore) : \(vm.blackScore)").font(.title3.bold())
                    Text("Black").foregroundStyle(Color(white: 0.55))
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                VStack(spacing: 8) {
                    Button("Rematch") { vm.rematch() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    Button("New Game") { vm.newGame() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }

            } else if vm.dice == nil {
                Button("New Game") { vm.newGame() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("Setup Board") { vm.enterSetupMode() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

            } else {
                Button("Setup Board") { vm.enterSetupMode() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }

            Spacer()
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func setupColorButton(_ color: Player, label: String) -> some View {
        let isSelected = vm.setupColor == color
        let isWhite    = color == .white
        return Button(label) { vm.setupColor = color }
            .font(.caption.bold())
            .foregroundStyle(isWhite ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isWhite ? Color.white : Color(white: 0.12))
                    .shadow(color: .black.opacity(isSelected ? 0.4 : 0.1), radius: isSelected ? 3 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
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
                    vm.cancelDrag()
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
                visible = true
                withAnimation(.easeInOut(duration: 0.25)) { animPos = dst }
                try? await Task.sleep(for: .milliseconds(300))
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
        default: return CGPoint(x: ptX(f.from), y: ptY(f.from))
        }
    }

    private func destCenter(for f: FlightInfo) -> CGPoint {
        switch f.to {
        case 0:  return CGPoint(x: boardW + cSz, y: boardH * 0.75)  // white bore-off (off right)
        case 25: return CGPoint(x: boardW + cSz, y: boardH * 0.25)  // black bore-off (off right)
        default: return CGPoint(x: ptX(f.to), y: ptY(f.to))
        }
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

    private func ptY(_ p: Int) -> CGFloat {
        (13...24).contains(p) ? cSz / 2 : boardH - cSz / 2
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
