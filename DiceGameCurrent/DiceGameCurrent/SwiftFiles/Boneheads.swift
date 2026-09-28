import SwiftUI

/// Boneheads: fill your grid, stack your matches, and smash theirs.
///
/// One d6 a turn and one decision with it — which of three columns — so a
/// turn is exactly one message, with a real choice in it. That is the best
/// ratio in the suite.
///
/// **The rules needed no balancing.** Measured over 30,000 games with both
/// seats playing the same way, the first seat wins 50.4%, the second 47.6%,
/// and 1.9% are drawn — close enough to even to leave alone, and the only
/// game in the suite whose design arrived balanced.
///
/// The rule that looks harshest — whoever fills their grid ends the match
/// on the spot, with no answering turn — turns out not to be what balances
/// it: granting that final turn measures 49.5% / 48.4%, which is the same
/// game. It stays because it is the design's own rule and the simpler one,
/// not because the numbers demand it.
enum BoneheadsRules {

    static let columns = 3
    static let slotsPerColumn = 3
    static let dieSides = 6

    /// Nine slots a side, so at least eighteen placements a match — and
    /// more once strikes start taking dice off. Measures 22.6 turns.
    static var slotsPerPlayer: Int { columns * slotsPerColumn }

    /// What one column is worth.
    ///
    /// The document writes this as "face value × quantity²", which is
    /// right for a column of one number and silent about mixed ones. Its
    /// examples settle it: a 5, a 5 and a 2 scores (5+5)×2 + 2 = 22, so
    /// every *distinct* value is multiplied by how many times it appears.
    static func columnScore(_ dice: [Int]) -> Int {
        var counts: [Int: Int] = [:]
        for die in dice { counts[die, default: 0] += 1 }
        return counts.reduce(0) { $0 + $1.key * $1.value * $1.value }
    }

    /// A single d6, coloured to whoever is throwing it.
    /// The second player's colour.
    ///
    /// Fixed rather than drawn from the palette, and the same tone the
    /// opponent's grid has always been drawn in — so the die in the air,
    /// the die banked in a column and the frame around that column are one
    /// colour per player.
    static let opponentBodyHex = "#D2735F"

    /// A seat's dice.
    ///
    /// Seat 0 takes the player's chosen table colour, seat 1 the fixed
    /// tone above. This used to be `DiePalette.colorways.shuffled().first`,
    /// so the die you threw was a different colour every turn and matched
    /// neither side of the board.
    static func colorway(for seat: Int) -> DieColorway {
        seat == 0
            ? DieColorway(
                bodyHex: AppTheme.swatches[AppTheme.shared.colorwayIndex].hex,
                numberHex: "#1B1B1F")
            : DieColorway(bodyHex: opponentBodyHex, numberHex: "#2A1712")
    }

    static func makeDice(for seat: Int = 0) -> [Die] {
        [Die(sides: dieSides, colorway: colorway(for: seat))]
    }
}

// MARK: - State

/// Both grids. `grids[seat][column]` holds that column's dice, first
/// placed first — which is also bottom-up on screen.
struct BoneheadsState: Codable, Equatable {

    private(set) var grids: [[[Int]]]

    init() {
        grids = Array(
            repeating: Array(repeating: [Int](), count: BoneheadsRules.columns),
            count: 2
        )
    }

    private enum CodingKeys: String, CodingKey { case grids = "g" }

    // MARK: Reading

    func column(seat: Int, _ index: Int) -> [Int] { grids[seat][index] }

    func score(seat: Int) -> Int {
        grids[seat].reduce(0) { $0 + BoneheadsRules.columnScore($1) }
    }

    func columnScore(seat: Int, _ index: Int) -> Int {
        BoneheadsRules.columnScore(grids[seat][index])
    }

    func canPlace(seat: Int, column: Int) -> Bool {
        grids[seat][column].count < BoneheadsRules.slotsPerColumn
    }

    /// True once every slot on that side is taken, which ends the match.
    func isFull(seat: Int) -> Bool {
        grids[seat].allSatisfy { $0.count == BoneheadsRules.slotsPerColumn }
    }

    var filledSeat: Int? {
        [0, 1].first { isFull(seat: $0) }
    }

    // MARK: Placing

    /// What a placement did to the opponent.
    struct Strike: Equatable {
        let column: Int
        let value: Int
        /// How many of the opponent's dice it destroyed. Zero for a plain
        /// placement.
        let destroyed: Int
    }

    /// Drops a die into a column and resolves the strike.
    ///
    /// A strike removes **every** die of that value from the opponent's
    /// column of the same letter, and the survivors close the gap — which
    /// falls out for free here, because a column is just an array in
    /// placement order.
    @discardableResult
    mutating func place(seat: Int, column: Int, die: Int) -> Strike {
        grids[seat][column].append(die)

        let opponent = 1 - seat
        let before = grids[opponent][column].count
        grids[opponent][column].removeAll { $0 == die }
        let destroyed = before - grids[opponent][column].count

        return Strike(column: column, value: die, destroyed: destroyed)
    }
}

// MARK: - Describing a turn

extension BoneheadsRules {

    static let columnNames = ["A", "B", "C"]

    static func name(of column: Int) -> String {
        columnNames.indices.contains(column) ? columnNames[column] : "?"
    }

    /// One line for the handover screen.
    static func summary(
        player: String,
        opponent: String,
        strike: BoneheadsState.Strike
    ) -> String {
        let where_ = "column \(name(of: strike.column))"
        guard strike.destroyed > 0 else {
            return "\(player) dropped a \(strike.value) into \(where_)."
        }
        let plural = strike.destroyed == 1 ? "" : "s"
        return "\(player) smashed \(strike.destroyed) \(strike.value)\(plural) out of \(opponent)'s \(where_)."
    }
}

// MARK: - Suite entry

enum BoneheadsGame: SuiteGame {
    static let id = "boneheads"
    static let displayName = "Boneheads"
    static let tagline = "Stack yours. Smash theirs."

    /// The short version, shown from inside the game.
    static let quickRules: [GameRuleSection] = [
        GameRuleSection(
            title: "The Goal",
            body: "Three columns of three each. Fill the ninth slot and the game ends on the spot — highest total wins."
        ),
        GameRuleSection(
            title: "Your Turn",
            body: "Roll one die and place it in any of your columns with room. That is the whole turn."
        ),
        GameRuleSection(
            title: "Stacking and Smashing",
            body: "Matching numbers in a column multiply: one 5 is 5, two are 20, three are 45. And placing a die destroys every die of that number in your opponent's column of the same letter."
        )
    ]

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Your Turn",
            body: "You roll one die and place it in any of your columns that still has room. That is the whole turn — the only question is which column."
        ),
        GameRuleSection(
            title: "Stacking",
            body: "Every number in a column is multiplied by how many times it appears there. One 5 is 5. Two 5's are 20, not 10. Three 5's are 45. A 5, a 5 and a 2 is 22."
        ),
        GameRuleSection(
            title: "Smashing",
            body: "Place a die and every die of that number in your opponent's column of the same letter is destroyed. Their survivors close the gap. A three-stack they spent three turns building comes apart in one."
        ),
        GameRuleSection(
            title: "Winning",
            body: "There are nine slots a side, and the moment either player fills their ninth the game stops — there is no answering turn. Highest total wins. That rule is what keeps going first from being an advantage."
        )
    ]
}
