import Foundation

struct Dice {

    // Full set of values for this roll (4 identical values for doubles).
    let values: [Int]

    // Dice still available to use this turn; consumed one at a time.
    private(set) var remaining: [Int]

    init() {
        let d1 = Int.random(in: 1...6)
        let d2 = Int.random(in: 1...6)
        values    = d1 == d2 ? [d1, d1, d1, d1] : [d1, d2]
        remaining = values
    }

    init(_ d1: Int, _ d2: Int) {
        values    = d1 == d2 ? [d1, d1, d1, d1] : [d1, d2]
        remaining = values
    }

    var isDoubles: Bool { values.count == 4 }
    var isDone: Bool    { remaining.isEmpty }

    mutating func markUsed(die: Int) {
        guard let idx = remaining.firstIndex(of: die) else { return }
        remaining.remove(at: idx)
    }
}
