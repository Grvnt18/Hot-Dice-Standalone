import Foundation

/// HOG: one die, and the only question that matters — roll again, or keep
/// what you have?
///
/// The shortest ruleset in the suite and the one that needs the least
/// explaining, which is exactly why it earns its tile. Its tension already
/// *is* the back-and-forth: every hold-or-roll decision is made against an
/// opponent's total you can see.
enum HogRules {

    /// First to bank this wins, on the spot.
    ///
    /// Measured at 14.8 messages a match with the first seat taking 54.5%.
    /// A final-turn catch-up rule was considered and dropped: it would even
    /// the seats out to 52.8% but costs two and a half more messages, and
    /// being cut off mid-comeback is part of what HOG is.
    static let target = 75

    /// Rolling this loses everything you have not banked.
    static let hogFace = 1

    /// One d6, in a colour picked fresh each match.
    static func makeDice() -> [Die] {
        guard let colorway = DiePalette.colorways.shuffled().first else { return [] }
        return [Die(sides: 6, colorway: colorway)]
    }
}

// MARK: - Describing a turn

extension HogRules {

    /// One line for the handover screen.
    static func summary(player: String, banked: Int, hogged: Bool) -> String {
        if hogged { return "\(player) rolled a 1 and lost the lot." }
        if banked == 0 { return "\(player) banked nothing." }
        return "\(player) banked \(banked)."
    }
}

/// HOG as it travels in a message.
///
/// Almost nothing, and that is the game rather than an oversight: every
/// point HOG keeps is banked into `TurnMatch.scores`, and a turn total is
/// the only thing that exists outside it. Carried anyway so a turn can be
/// handed over mid-push rather than only at a hold — the receiver sees
/// what is riding on the next roll.
///
/// The die in the air does not travel. A roll is resolved on the device
/// that threw it and the face is already folded into `turnTotal`.
struct HogState: Codable, Equatable {

    /// Points accumulated this turn and not yet banked. Zero at a handover
    /// that followed a hold or a Hog.
    var turnTotal: Int = 0

    private enum CodingKeys: String, CodingKey { case turnTotal = "t" }

    init(turnTotal: Int = 0) { self.turnTotal = turnTotal }
}

// MARK: - Suite entry

enum HogGame: SuiteGame {
    static let id = "hog"
    static let displayName = "Hog"
    static let tagline = "Be greedy, but don't let the Hog eat your points."

    /// Two or more, per GAME_RULES.txt. The turns alternate and the state
    /// is per seat, so nothing here is counting to two — see
    /// TurnMatch.local(playerCount:).
    static let maxPlayers = Int.max

    /// Pass-and-play seats the gate offers: as many as the scoreboard
    /// fits, which `MatchSetup.maxSeats` decides. `Int.max` here is the
    /// same claim `maxPlayers` makes, and it is true of this screen too —
    /// it hosts a `TurnMatch` and labels every seat in it.
    static let localSeats = Int.max

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "  * Players: 2 or more (alternating turns).\n  * Dice Pool: 1x d6.\n  * Objective: First player to bank 75 points wins instantly."
        ),
        GameRuleSection(
            title: "Mechanics",
            body: "  1. Roll the die.\n  2. Roll 2-6: Add value to running turn total. Choose to roll again or hold.\n  3. Roll 1 (Hog): Turn ends immediately and all points accumulated during\n     that turn are eaten by the Hog. Banked score is unaffected.\n  4. Hold: Bank running turn score into overall score and end turn."
        )
    ]
}
