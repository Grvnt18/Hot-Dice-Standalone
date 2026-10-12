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

    /// The second seat's colour, for its FURNITURE — its column letters and
    /// its running totals, not its dice.
    ///
    /// Two scoreboards on one screen still need telling apart, and that is
    /// all this is for now. The dice stopped using it when they started
    /// carrying their own ink.
    static let secondSeatHex = "#D2735F"

    /// A die's colour, by its index into the shared palette.
    ///
    /// Colour used to mean *seat*: yours took the table colour, theirs a
    /// fixed clay, and the column frames matched. That was itself a
    /// correction — before it, the colour was reshuffled every turn and
    /// matched neither side of the board.
    ///
    /// It is random again now, deliberately, with the thing that broke it
    /// last time fixed rather than reverted: a placed die KEEPS the colour
    /// it was thrown in (see `Placement.ink`), and the frames no longer
    /// claim a colour at all. Ownership is read from position — your three
    /// columns are on your side of the board — which it always could have
    /// been, and colour is free to be colour.
    static func colorway(ink: Int) -> DieColorway {
        let palette = DiePalette.colorways
        return palette[((ink % palette.count) + palette.count) % palette.count]
    }

    /// A fresh colour for a throw.
    ///
    /// An index rather than a DieColorway because this travels: it is
    /// stored with the placement and sent over the wire, and one Int is
    /// both smaller and impossible to get subtly wrong against a palette
    /// that gains an entry later.
    static func randomInk() -> Int {
        Int.random(in: 0..<DiePalette.colorways.count)
    }

    static func makeDice(ink: Int) -> [Die] {
        [Die(sides: dieSides, colorway: colorway(ink: ink))]
    }
}

// MARK: - State

/// A die in a column: the face it shows, and the colour it was thrown in.
///
/// The colour is stored rather than derived, which is the whole of the fix.
/// A banked die used to be drawn in whatever colour its SEAT was using at
/// the time, so once throws became random the board would have re-coloured
/// itself under the player every turn. Keeping the ink with the die means
/// the one in the column is the one you threw.
///
/// `ink` is an index into `DiePalette.colorways`, not a colour: this is
/// Codable and goes over the wire.
struct BoneheadsPlacement: Codable, Equatable {
    let face: Int
    let ink: Int

    private enum CodingKeys: String, CodingKey {
        case face = "f"
        case ink = "i"
    }
}

/// Both grids. `grids[seat][column]` holds that column's dice, first
/// placed first — which is also bottom-up on screen.
struct BoneheadsState: Codable, Equatable {

    private(set) var grids: [[[BoneheadsPlacement]]]

    init() {
        grids = Array(
            repeating: Array(repeating: [BoneheadsPlacement](),
                             count: BoneheadsRules.columns),
            count: 2
        )
    }

    private enum CodingKeys: String, CodingKey { case grids = "g" }

    // MARK: Reading

    func column(seat: Int, _ index: Int) -> [BoneheadsPlacement] {
        grids[seat][index]
    }

    /// The faces in a column, which is all the scoring and the smash care
    /// about — colour is for the eye only and never changes a result.
    func faces(seat: Int, _ index: Int) -> [Int] {
        grids[seat][index].map(\.face)
    }

    func score(seat: Int) -> Int {
        grids[seat].reduce(0) {
            $0 + BoneheadsRules.columnScore($1.map(\.face))
        }
    }

    func columnScore(seat: Int, _ index: Int) -> Int {
        BoneheadsRules.columnScore(faces(seat: seat, index))
    }

    func canPlace(seat: Int, column: Int) -> Bool {
        grids[seat][column].count < BoneheadsRules.slotsPerColumn
    }

    /// True once every slot on that side is taken, which ends the match.
    func isFull(seat: Int) -> Bool {
        grids[seat].allSatisfy { $0.count == BoneheadsRules.slotsPerColumn }
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
    mutating func place(seat: Int, column: Int, die: Int, ink: Int) -> Strike {
        grids[seat][column].append(BoneheadsPlacement(face: die, ink: ink))

        let opponent = 1 - seat
        let before = grids[opponent][column].count
        // Faces only. Two dice of the same number smash each other whatever
        // colours they happen to be wearing.
        grids[opponent][column].removeAll { $0.face == die }
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

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "  * Players: 2.\n  * Board Layout: 3 columns per player (A, B, C), 3 slots each (9 slots total).\n  * Objective: Fill all slots while maximizing column scoring multipliers and\n    destroying opponent dice."
        ),
        GameRuleSection(
            title: "Mechanics",
            body: "  Roll 1x d6 and place it into any available slot in your columns to end turn.\n\n  Smashing: Placing a die in a column destroys all matching dice in opponent's directly\n  opposing column. Remaining opponent dice collapse down to fill gaps.\n  Game End: Immediately when either player fills their 9th slot. Highest score wins."
        ),
        GameRuleSection(
            title: "Column Stacking Multipliers",
            body: "  Matching numbers in same column multiply combined value:\n    Column Score = (Die Face x Occurrences) x Occurrences\n    * Single Die: Face Value (1x)\n    * Pair: (Face x 2) x 2\n    * Triple: (Face x 3) x 3",
            figures: [.boneheadsScoring]
        )
    ]
}
