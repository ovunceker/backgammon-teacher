import SwiftUI

// Top row (L→R): 13–18 | BAR | 19–24    Bottom row (L→R): 12–7 | BAR | 6–1
private let topLeft  = [13, 14, 15, 16, 17, 18]; private let topRight = [19, 20, 21, 22, 23, 24]
private let botLeft  = [12, 11, 10,  9,  8,  7]; private let botRight = [ 6,  5,  4,  3,  2,  1]

// MARK: - BoardView

struct BoardView: View {
    @Environment(GameViewModel.self) private var vm

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
    }

    // MARK: Board

    private func boardCanvas(W: CGFloat, ptW: CGFloat, ptH: CGFloat, barW: CGFloat, cSz: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.42, green: 0.24, blue: 0.10))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            HStack(spacing: 0) {
                halfPanel(top: topLeft, bot: botLeft, ptW: ptW, ptH: ptH, cSz: cSz)
                barPanel(barW: barW, ptH: ptH, cSz: cSz)
                halfPanel(top: topRight, bot: botRight, ptW: ptW, ptH: ptH, cSz: cSz)
            }
            if let d = vm.dice, !d.remaining.isEmpty {
                diceOverlay(dice: d, ptW: ptW, barW: barW)
            }
        }
        .frame(width: W, height: ptH * 2 + 20)
    }

    private func halfPanel(top: [Int], bot: [Int], ptW: CGFloat, ptH: CGFloat, cSz: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(top, id: \.self) { PointView(point: $0, isTop: true,  ptW: ptW, ptH: ptH, cSz: cSz) }
            }
            Spacer(minLength: 20)
            HStack(spacing: 0) {
                ForEach(bot, id: \.self) { PointView(point: $0, isTop: false, ptW: ptW, ptH: ptH, cSz: cSz) }
            }
        }
        .frame(width: ptW * 6)
    }

    private func barPanel(barW: CGFloat, ptH: CGFloat, cSz: CGFloat) -> some View {
        VStack {
            barCheckers(.black, barW: barW, cSz: cSz)
            Spacer()
            barCheckers(.white, barW: barW, cSz: cSz)
        }
        .padding(.vertical, 6)
        .frame(width: barW, height: ptH * 2 + 20)
        .background(Color(red: 0.26, green: 0.14, blue: 0.05))
    }

    @ViewBuilder
    private func barCheckers(_ player: Player, barW: CGFloat, cSz: CGFloat) -> some View {
        let count = player == .white ? vm.state.whiteBar : vm.state.blackBar
        let pt    = player.barPoint
        let sz    = min(barW * 0.78, cSz)
        VStack(spacing: 2) {
            ForEach(0..<min(count, 3), id: \.self) { _ in
                Circle()
                    .fill(player == .white ? Color.white : Color(white: 0.12))
                    .overlay(Circle().stroke(player == .white ? Color.gray : Color(white: 0.55), lineWidth: 1))
                    .frame(width: sz, height: sz)
            }
            if count > 3 { Text("+\(count - 3)").font(.caption2.bold()).foregroundColor(.white) }
        }
        .padding(3)
        .background(vm.selectedPoint == pt ? Color.yellow.opacity(0.45) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4))
        .onTapGesture { if count > 0 { vm.tap(point: pt) } }
    }

    // MARK: On-board dice

    // Dice are centered in the right half for white, left half for black.
    private func diceOverlay(dice: Dice, ptW: CGFloat, barW: CGFloat) -> some View {
        let isWhite = vm.state.currentPlayer == .white
        let dSz: CGFloat = min(ptW * 0.85, 48)
        let xOff = ptW * 3 + barW / 2   // distance from board centre to half-panel centre
        return diceContent(dice: dice, dSz: dSz)
            .offset(x: isWhite ? xOff : -xOff)
    }

    @ViewBuilder
    private func diceContent(dice: Dice, dSz: CGFloat) -> some View {
        let vals = dice.remaining
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
            boreOffSection(player: .black, sz: min(trayW * 0.78, cSz), ptH: ptH)
            Spacer(minLength: 20)
            boreOffSection(player: .white, sz: min(trayW * 0.78, cSz), ptH: ptH)
        }
        .frame(width: trayW, height: ptH * 2 + 20)
        .background(Color(red: 0.26, green: 0.14, blue: 0.05))
    }

    @ViewBuilder
    private func boreOffSection(player: Player, sz: CGFloat, ptH: CGFloat) -> some View {
        let count  = player == .white ? vm.state.whiteBorneOff : vm.state.blackBorneOff
        let maxVis = max(1, Int((ptH - 8) / (sz + 3)))
        let vis    = min(count, maxVis)
        ZStack(alignment: player == .black ? .top : .bottom) {
            Color.clear.frame(height: ptH)
            if count > 0 {
                VStack(spacing: 3) {
                    ForEach(0..<vis, id: \.self) { _ in
                        Circle()
                            .fill(player == .white ? Color.white : Color(white: 0.12))
                            .overlay(Circle().stroke(player == .white ? Color.gray : Color(white: 0.55), lineWidth: 1))
                            .frame(width: sz, height: sz)
                    }
                    if count > maxVis {
                        Text("+\(count - maxVis)").font(.caption2.bold()).foregroundColor(.white)
                    }
                }
                .padding(4)
            }
        }
    }

    // MARK: Control panel (right side)

    @ViewBuilder
    private var controlPanel: some View {
        VStack(spacing: 14) {
            // Turn indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.state.currentPlayer == .white ? Color.white : Color.black)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 14, height: 14)
                Text(vm.state.currentPlayer == .white ? "White's turn" : "Black's turn")
                    .font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons
            VStack(spacing: 8) {
                if vm.canRoll {
                    Button("Roll Dice") { vm.rollDice() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                if vm.legalDestinations.contains(vm.state.currentPlayer.boreOffPoint) {
                    Button("Bear Off") { vm.tapBoreOff() }
                        .buttonStyle(.bordered).tint(.orange)
                        .frame(maxWidth: .infinity)
                }
                if vm.canUndo {
                    Button("Undo") { vm.undoStep() }
                        .buttonStyle(.bordered).tint(.red)
                        .frame(maxWidth: .infinity)
                }
                if vm.pendingEndTurn {
                    Button("Done") { vm.confirmEndTurn() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }

            if let w = vm.state.winner {
                Text("\(w == .white ? "White" : "Black") wins!")
                    .font(.headline.bold())
                    .multilineTextAlignment(.center)
                Button("New Game") { vm.newGame() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }

            Spacer()
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - PointView

private struct PointView: View {
    let point: Int
    let isTop: Bool
    let ptW: CGFloat
    let ptH: CGFloat
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
        .onTapGesture { vm.tap(point: point) }
    }

    private var triColor: Color {
        point % 2 == 0
            ? Color(red: 0.62, green: 0.08, blue: 0.06)   // deep burgundy
            : Color(red: 0.94, green: 0.87, blue: 0.68)   // warm cream
    }

    @ViewBuilder
    private var checkerStack: some View {
        let n = abs(raw)
        let isWhite = raw > 0
        if n > 0 {
            // step: visible height each checker contributes; shrinks to fit all within ptH
            let step: CGFloat = n > 1 ? min(cSz * 0.72, (ptH - cSz) / CGFloat(n - 1)) : cSz
            VStack(spacing: step - cSz) {
                if isTop {
                    ForEach(0..<n, id: \.self) { _ in checkerDisc(isWhite: isWhite) }
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    ForEach(0..<n, id: \.self) { _ in checkerDisc(isWhite: isWhite) }
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

private struct DiceFaceView: View {
    let value: Int
    var size: CGFloat = 44

    // Dot offsets as fractions of size, relative to face centre (0,0).
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
        let r = size * 0.18
        ZStack {
            RoundedRectangle(cornerRadius: r)
                .fill(LinearGradient(
                    colors: [Color(white: 0.97), Color(white: 0.80)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: r)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
            if value >= 1, value <= 6 {
                ForEach(DiceFaceView.dots[value].indices, id: \.self) { i in
                    let (dx, dy) = DiceFaceView.dots[value][i]
                    Circle()
                        .fill(Color(white: 0.10))
                        .frame(width: size * 0.15, height: size * 0.15)
                        .offset(x: dx * size, y: dy * size)
                }
            }
        }
        .frame(width: size, height: size)
        // Hard offset shadow = simulated die edge; soft shadow = depth
        .shadow(color: Color(white: 0.22).opacity(0.85), radius: 0, x: size * 0.06, y: size * 0.06)
        .shadow(color: .black.opacity(0.30), radius: 4, x: 1, y: 2)
    }
}
