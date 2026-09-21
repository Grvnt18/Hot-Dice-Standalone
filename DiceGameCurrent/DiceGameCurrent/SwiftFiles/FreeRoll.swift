import Foundation

/// The dice the player has chosen for a Free Roll session.
///
/// A sandbox, not a game: no scoring, no banking, no turn structure. Pick up
/// to 10 dice in any combination and throw them as often as you like.
struct FreeRollPool: Equatable {

    /// Ten is the cap the design settled on, and it is also comfortably
    /// inside what the spawn pattern lays out cleanly —
    /// `DiceSpawnPattern` fills rows of 5, 4, 3, 2, 1, so 10 dice occupy
    /// the first three rows with room to spare.
    static let maxDice = 10

    /// Every die the app has a mesh for. d4 and d20 were built earlier for
    /// the wider project and have no use in Rolls itself — this is the
    /// first place they are actually rollable.
    static let availableSides = [4, 6, 8, 10, 12, 20]

    /// sides -> how many of that die.
    private(set) var counts: [Int: Int]

    /// Two d6 is the most familiar thing to open on, and it makes the
    /// playfield obviously alive without the player choosing anything.
    static let `default` = FreeRollPool(counts: [6: 2])

    init(counts: [Int: Int] = [:]) {
        self.counts = counts.filter { $0.value > 0 }
    }

    var total: Int {
        counts.values.reduce(0, +)
    }

    var isFull: Bool { total >= Self.maxDice }

    var isEmpty: Bool { total == 0 }

    func count(of sides: Int) -> Int {
        counts[sides] ?? 0
    }

    mutating func add(_ sides: Int) {
        guard !isFull else { return }
        counts[sides, default: 0] += 1
    }

    mutating func remove(_ sides: Int) {
        guard let current = counts[sides], current > 0 else { return }
        if current == 1 {
            counts.removeValue(forKey: sides)
        } else {
            counts[sides] = current - 1
        }
    }

    mutating func clear() {
        counts.removeAll()
    }

    /// Turns the selection into actual dice.
    ///
    /// Colourways come from a shuffled `DiePalette` rather than being
    /// assigned by die type, so two d6 in the same pool are still visually
    /// distinct. With a cap of 10 against 15 colourways, every die in a
    /// pool is guaranteed a different colour.
    func makeDice() -> [Die] {
        var colorways = DiePalette.colorways.shuffled()
        var dice: [Die] = []
        dice.reserveCapacity(total)

        // Sorted so the same selection always produces the same die order;
        // dictionary iteration order is not stable, and an unstable order
        // would mean re-picking the identical pool reshuffled the board for
        // no visible reason.
        for sides in counts.keys.sorted() {
            for _ in 0..<(counts[sides] ?? 0) {
                // The guard is belt-and-braces: 10 dice can never exhaust
                // 15 colourways, but popping an empty array would trap.
                guard !colorways.isEmpty else { break }
                dice.append(Die(sides: sides, colorway: colorways.removeLast()))
            }
        }
        return dice
    }
}

// MARK: - Suite entry

enum FreeRollGame: SuiteGame {
    static let id = "freeroll"
    static let displayName = "Free Roll"
    static let tagline = "Up to 10 dice. No score. Just roll."

    /// The one game in the suite that cannot be sent.
    ///
    /// It has no opponent and no state anyone else would act on — there is
    /// nothing to put in a message. This is the property's reason for
    /// existing on `SuiteGame`.
    static let isSendable = false

    /// Solo. Not a limit anyone bumps into, but stating it keeps the
    /// protocol honest rather than letting the two-player default stand.
    static let maxPlayers = 1

    static let rules: [String] = [
        "Pick up to 10 dice in any combination — d4, d6, d8, d10, d12, d20.",
        "Roll them as many times as you like. Nothing is banked and nothing is scored.",
        "Change the dice whenever you want; the table is rebuilt with your new picks."
    ]
}
