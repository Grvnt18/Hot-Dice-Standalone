import Foundation

// MARK: - Die color palette

/// 15 unique (body color, number color) pairs, one permanently assigned per
/// physical die. Body colors come from a specific, requested palette —
/// https://javier.xyz/cohesive-colors — 15 source colors run through that
/// tool's "overlay" blend (base color combined with #FF9C00 via a
/// multiply+screen Overlay blend, then lerped 30% toward that blended
/// result) for a cohesive, unified feel across the whole set. Computed
/// directly (verified the tool's underlying colorblendjs algorithm rather
/// than eyeballing it) since the tool itself is client-side JS with no
/// server-side API to call. Number colors are computed per-body-color for
/// WCAG relative luminance contrast (dark text on light bodies, light text
/// on dark bodies) — no longer manually curated per swatch, since the
/// specific body colors are now fixed by the requested palette rather than
/// freely chosen.
struct DieColorway: Equatable {
    let bodyHex: String
    let numberHex: String
}

enum DiePalette {
    static let colorways: [DieColorway] = [
        DieColorway(bodyHex: "#6E6456", numberHex: "#F5F5F5"),
        DieColorway(bodyHex: "#CCDB48", numberHex: "#1B1B1B"),
        DieColorway(bodyHex: "#CB7D94", numberHex: "#F5F5F5"),
        DieColorway(bodyHex: "#9A593A", numberHex: "#F5F5F5"),
        DieColorway(bodyHex: "#FDE558", numberHex: "#1B1B1B"),
        DieColorway(bodyHex: "#A1CFDD", numberHex: "#1B1B1B"),
        DieColorway(bodyHex: "#DB362C", numberHex: "#F5F5F5"),
        DieColorway(bodyHex: "#FFA23F", numberHex: "#1B1B1B"),
        DieColorway(bodyHex: "#D33AFD", numberHex: "#F5F5F5"),
        DieColorway(bodyHex: "#7CBD7B", numberHex: "#1B1B1B"),
        DieColorway(bodyHex: "#A88E65", numberHex: "#F5F5F5"),
        DieColorway(bodyHex: "#D2735F", numberHex: "#F5F5F5"),
        DieColorway(bodyHex: "#FBD365", numberHex: "#1B1B1B"),
        DieColorway(bodyHex: "#FCFBF9", numberHex: "#1B1B1B"),
        DieColorway(bodyHex: "#00ADB4", numberHex: "#F5F5F5")
    ]
}

// MARK: - Die

struct Die: Identifiable, Equatable {
    let id: UUID = UUID()
    let sides: Int              // 6, 8, 10, or 12
    let colorway: DieColorway   // permanent, unique per physical die
    var currentValue: Int?      // nil until settled — now set from the physically-landed face, see DiceGameRound.setValue(for:value:)

    /// Points scored if this die is banked right now.
    /// Rolling the max face = 0 pts, each face below that = +1.
    var pointValue: Int? {
        guard let value = currentValue else { return nil }
        // Rolling the maximum face scores 0; every face below it scores
        // more. A 1 is special-cased to the die's own maximum rather than
        // sides - 1, so it's the single worst result you can take on any
        // die — a 1 on a d12 costs 12, not 11.
        return value == 1 ? sides : sides - value
    }
}

// MARK: - Game State

final class DiceGameRound {

    private(set) var pool: [Die]
    private(set) var bankedScore: Int = 0
    private(set) var hasRolledThisTurn: Bool = false

    /// Dice in the order they were banked, for the 3x5 history grid.
    /// Each entry's colorway ties back to DiePalette so a specific physical
    /// die can be traced across the grid regardless of its sides/type.
    private(set) var bankedOrder: [Die] = []

    init() {
        // 12 D6, 1 D8, 1 D10, 1 D12 = 15 dice total, each given a unique
        // permanent colorway from the 15-entry palette.
        var colorways = DiePalette.colorways
        colorways.shuffle()

        var sideCounts: [Int] = Array(repeating: 6, count: 12) + [8, 10, 12]
        sideCounts.shuffle() // so colorway assignment isn't correlated with die type

        self.pool = zip(sideCounts, colorways).map { sides, colorway in
            Die(sides: sides, colorway: colorway)
        }
    }

    var isGameOver: Bool {
        pool.isEmpty
    }

    /// Marks a new roll as in progress. Values are no longer pre-randomized
    /// here — per your latest design change, the true result now comes
    /// from whichever face physically lands up (read via
    /// setValue(for:value:), called once each die's settle/face-snap
    /// completes). This just flips the "a roll has started" flag that
    /// gates the Roll button / selection UI; currentValue for each die
    /// stays nil until physics actually determines it.
    func rollPool() {
        guard !isGameOver else { return }
        hasRolledThisTurn = true
    }

    /// Called once a die has physically settled and face-snapped — writes
    /// the value read from whichever face landed up as this die's true
    /// scored result.
    func setValue(for dieID: UUID, value: Int) {
        guard let index = pool.firstIndex(where: { $0.id == dieID }) else { return }
        pool[index].currentValue = value
    }

    /// Bank one or more dice from the current roll for score, removing them from the pool.
    /// Enforces the "must bank at least 1 die per roll" rule at the call site —
    /// the UI should require selectedIDs.count >= 1 before allowing a re-roll.
    @discardableResult
    func bank(dieIDs: Set<UUID>) -> Int {
        guard hasRolledThisTurn, !dieIDs.isEmpty else { return 0 }

        let toBank = pool.filter { dieIDs.contains($0.id) && $0.currentValue != nil }
        let points = toBank.compactMap { $0.pointValue }.reduce(0, +)

        pool.removeAll { dieIDs.contains($0.id) }
        bankedOrder.append(contentsOf: toBank) // preserves banking order for the grid
        bankedScore += points
        hasRolledThisTurn = false // must reroll remaining pool before banking again

        return points
    }
}
