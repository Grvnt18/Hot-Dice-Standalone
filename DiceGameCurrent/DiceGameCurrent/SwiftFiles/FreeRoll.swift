import Foundation

/// The dice the player has chosen for a Free Roll session.
///
/// A sandbox, not a game: no scoring, no banking, no turn structure. Pick up
/// to `maxDice` in any combination and throw them as often as you like.
struct FreeRollPool: Equatable {

    /// Twenty, matching the spawn pattern's slot count exactly — see
    /// DiceSpawnPattern.rowCounts, which was extended to hold them
    /// without overlap.
    static let maxDice = 20

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
    /// distinct.
    ///
    /// **The palette is refilled rather than exhausted.** There are 15
    /// colourways and the cap is 20, so the last five dice used to hit a
    /// `guard !colorways.isEmpty else { break }` and simply not be created
    /// — a pool of 20 put 15 dice on the table, with no error and nothing
    /// to see but a count that did not match. That guard was written when
    /// the cap was 10 and was correct then; the cap moved and it did not.
    ///
    /// Refilling means a 16th die repeats a colour, which is the right
    /// trade: two dice sharing a shade is a cosmetic compromise, five dice
    /// missing is a broken pool.
    func makeDice() -> [Die] {
        var colorways: [DieColorway] = []
        var dice: [Die] = []
        dice.reserveCapacity(total)

        // Sorted so the same selection always produces the same die order;
        // dictionary iteration order is not stable, and an unstable order
        // would mean re-picking the identical pool reshuffled the board for
        // no visible reason.
        for sides in counts.keys.sorted() {
            for _ in 0..<(counts[sides] ?? 0) {
                if colorways.isEmpty {
                    colorways = DiePalette.colorways.shuffled()
                }
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
    static let tagline = "Up to \(FreeRollPool.maxDice) dice. No score. Just roll."

    /// The one game in the suite that cannot be sent.
    ///
    /// It has no opponent and no state anyone else would act on — there is
    /// nothing to put in a message. This is the property's reason for
    /// existing on `SuiteGame`.
    static let isSendable = false

    /// Solo. Not a limit anyone bumps into, but stating it keeps the
    /// protocol honest rather than letting the two-player default stand.
    static let maxPlayers = 1

    /// Nobody to seat, so the setup gate skips itself — see
    /// `MatchSetupGate`. There is no `TurnMatch` on this screen and
    /// nothing on it is labelled with a name.
    static let localSeats = 1

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Overview",
            body: "  * Players: 1.\n  * Pool Limit: Up to 20 total dice (Selectable mix of d4, d6, d8, d10, d12, d20).\n  * Function: Open sandbox mode without scoring, win conditions, or turn limits.\n    Includes optional subtotals toggle per die type."
        )
    ]
}
