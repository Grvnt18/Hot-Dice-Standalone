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
    static let floorMotif = FloorMotif.pigFace
    static let id = "hog"
    static let displayName = "Hog"
    static let tagline = "Push your luck to 75."

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "At a Glance",
            body: "First to bank 75 wins immediately. Roll one die as often as you dare, adding each face to your turn total, then hold to bank it and pass. Roll a 1 — the Hog — and the whole turn total is gone."
        ),
        GameRuleSection(
            title: "Your Turn",
            body: "Roll one die as many times as you dare. Every face adds to your turn total — and you keep none of it until you hold."
        ),
        GameRuleSection(
            title: "The Hog",
            body: "Roll a 1 and the turn ends immediately with nothing. Everything you built up that turn is gone; your banked score is safe."
        ),
        GameRuleSection(
            title: "Holding",
            body: "Hold at any time to add your turn total to your score and pass the die. Holding is never wrong, only expensive."
        ),
        GameRuleSection(
            title: "Winning",
            body: "First to bank 75 wins on the spot — there is no answering turn, so a lead you can see is a lead you have to catch before they hold."
        )
    ]
}
