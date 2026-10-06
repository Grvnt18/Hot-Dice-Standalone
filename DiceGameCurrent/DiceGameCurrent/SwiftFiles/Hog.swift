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

// MARK: - Suite entry

enum HogGame: SuiteGame {
    static let id = "hog"
    static let displayName = "Hog"
    static let tagline = "Push your luck to 75."

    /// Two or more, per GAME_RULES.txt. The turns alternate and the state
    /// is per seat, so nothing here is counting to two — see
    /// TurnMatch.local(playerCount:).
    static let maxPlayers = Int.max


    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "Two or more players, alternating turns. The dice pool is one d6. The first player to bank 75 points wins instantly."
        ),
        GameRuleSection(
            title: "Turn Mechanics",
            body: "Roll the die. On a roll of 2 to 6, add the value to your running turn total, then choose to roll again or hold. On a roll of 1, the Hog, the turn ends immediately and all points accumulated during that turn are lost — your banked score is unaffected. Hold to bank the running turn total into your overall score and end the turn."
        )
    ]
}
