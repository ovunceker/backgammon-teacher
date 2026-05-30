import Foundation

// Encodes a BoardState into the 200-float vector the TDGammon CoreML model expects.
// Mirrors encode_board() + flip_board() from Net.ipynb exactly.
struct BoardEncoder {

    static func encode(_ state: BoardState, player: Player, cube: Int = 1, cubeOwner: Player? = nil) -> [Float] {
        // Build the raw 26-element board array (same sign convention as Python):
        // index 0 = white bar count, index 25 = black bar count, index 1-24 = points
        var board = [Int](repeating: 0, count: 26)
        board[0]  = state.whiteBar
        board[25] = state.blackBar
        for i in 1...24 { board[i] = state.points[i] }

        // Flip so the encoding is always from the current player's perspective
        if player == .black { board = flip(board) }

        var inputs = [Float]()
        inputs.reserveCapacity(200)

        var mineOnBoard = 0
        var oppOnBoard  = 0

        for i in 1...24 {
            let n     = board[i]
            let mine  = max(n, 0)
            inputs.append(mine >= 1 ? 1.0 : 0.0)
            inputs.append(mine >= 2 ? 1.0 : 0.0)
            inputs.append(mine >= 3 ? 1.0 : 0.0)
            inputs.append(Float(max(mine - 3, 0)) / 2.0)
            mineOnBoard += mine

            let theirs = max(-n, 0)
            inputs.append(theirs >= 1 ? 1.0 : 0.0)
            inputs.append(theirs >= 2 ? 1.0 : 0.0)
            inputs.append(theirs >= 3 ? 1.0 : 0.0)
            inputs.append(Float(max(theirs - 3, 0)) / 2.0)
            oppOnBoard += theirs
        }

        // After flip: board[0] = my bar, board[25] = opponent bar
        let myOff  = 15 - mineOnBoard - board[0]
        let oppOff = 15 - oppOnBoard  - board[25]

        inputs.append(Float(board[0])  / 2.0)
        inputs.append(Float(board[25]) / 2.0)
        inputs.append(Float(myOff)     / 15.0)
        inputs.append(Float(oppOff)    / 15.0)
        inputs.append(player == .white ? 1.0 : 0.0)
        inputs.append(Float(cube)      / 64.0)
        inputs.append(cubeOwner == player ? 1.0 : 0.0)  // I own the cube
        inputs.append(cubeOwner == nil    ? 1.0 : 0.0)  // cube is centred

        return inputs  // 200 floats
    }

    // Mirrors flip_board(): reflects the board and swaps checker colours,
    // so the encoding is always from "my pieces are positive" perspective.
    private static func flip(_ board: [Int]) -> [Int] {
        var b = [Int](repeating: 0, count: 26)
        b[0]  = board[25]
        b[25] = board[0]
        for i in 1...24 { b[i] = -board[26 - i] }
        return b
    }
}
