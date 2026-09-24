import Foundation

/// Jackpot: roll a polyhedral set, score matching sets, chase the Jackpot.
///
/// Five rounds each, alternating, so you see your opponent's round before
/// you roll yours.
enum JackpotRules {

    static let roundsPerPlayer = 5

    /// One set per player. The d4 is read as three numbers, not one — see
    /// `numbers(from:)`.
    static let dieSides = [4, 6, 8, 12, 20]

    /// At or above this, the d20 adds its face value to the turn. Put
    /// another way, the d20's top eight faces boost and the rest do not.
    static let boosterThreshold = 13

    /// At or below this, a no-match roll is a Jackpot.
    ///
    /// Deliberately one below the booster rather than two. With the
    /// original 11 there was a dead band at exactly 12: a no-match roll
    /// with d20 = 12 got neither the booster nor the Jackpot and scored a
    /// flat zero, which is 0.63% of all rolls landing on nothing at all.
    /// Meeting the booster closes it and makes the rule a single sentence —
    /// low d20 jackpots, high d20 boosts.
    static let jackpotThreshold = boosterThreshold - 1   // 12
}

// MARK: - Reading the dice

extension JackpotRules {

    /// The seven numbers a settled set produces.
    ///
    /// Four dice contribute their top face. The d4 contributes three: the
    /// numbers on the faces you can see, which are every face except the
    /// one against the table. `DiceTraySession` reports a d4's resting
    /// face rather than a reading, precisely so this can ask for the
    /// interpretation it wants.
    ///
    /// Those three are always distinct, so the d4 can never match itself —
    /// only the other dice.
    static func numbers(from results: [DiceTraySession.DieResult]) -> [Int] {
        var numbers: [Int] = []
        for result in results {
            if result.sides == 4 {
                numbers += DieFaceLabels.d4ExposedFaceNumbers(restingFace: result.value - 1)
            } else {
                numbers.append(result.value)
            }
        }
        return numbers
    }

    /// The d20's top face, or nil if the set had none.
    static func d20Face(from results: [DiceTraySession.DieResult]) -> Int? {
        results.first(where: { $0.sides == 20 })?.value
    }
}

// MARK: - Scoring

extension JackpotRules {

    struct TurnScore: Equatable {
        /// Points from matching sets.
        let setPoints: Int
        /// The d20's face, if it boosted.
        let booster: Int?
        /// True when the roll had no sets and a low d20.
        let isJackpot: Bool
        /// What the sets were, for the turn summary: value and how many.
        let sets: [(value: Int, count: Int)]

        var total: Int { setPoints + (booster ?? 0) }

        static func == (lhs: TurnScore, rhs: TurnScore) -> Bool {
            lhs.setPoints == rhs.setPoints
                && lhs.booster == rhs.booster
                && lhs.isJackpot == rhs.isJackpot
                && lhs.sets.map(\.value) == rhs.sets.map(\.value)
                && lhs.sets.map(\.count) == rhs.sets.map(\.count)
        }
    }

    /// Scores one roll.
    ///
    /// A set is any number appearing twice or more across the seven, and it
    /// scores that number times how many times it appears — two 4s is 8, a
    /// set of three 3s is 9.
    static func score(numbers: [Int], d20: Int?) -> TurnScore {
        var counts: [Int: Int] = [:]
        for number in numbers { counts[number, default: 0] += 1 }

        let sets = counts
            .filter { $0.value >= 2 }
            .map { (value: $0.key, count: $0.value) }
            // Sorted for a stable, readable summary — dictionary order is
            // not stable, and the same roll should always describe itself
            // the same way.
            .sorted { ($0.count, $0.value) > ($1.count, $1.value) }

        let setPoints = sets.reduce(0) { $0 + $1.value * $1.count }
        let hasSets = !sets.isEmpty

        let booster: Int? = {
            guard let d20, d20 >= boosterThreshold else { return nil }
            return d20
        }()

        let isJackpot = !hasSets && (d20 ?? 0) <= jackpotThreshold

        return TurnScore(
            setPoints: setPoints,
            booster: booster,
            isJackpot: isJackpot,
            sets: sets
        )
    }

    /// One line describing what a turn did, for the handover screen.
    static func summary(for score: TurnScore, player: String) -> String {
        if score.isJackpot { return "\(player) hit the Jackpot!" }
        var parts: [String] = []
        if !score.sets.isEmpty {
            parts.append(score.sets
                .map { "a set of \($0.count) \($0.value)'s" }
                .joined(separator: " and "))
        }
        if let booster = score.booster {
            parts.append("a \(booster) booster")
        }
        if parts.isEmpty { return "\(player) scored nothing." }
        return "\(player) rolled " + parts.joined(separator: ", ") + " — \(score.total) points."
    }
}

// MARK: - Jackpot resolution

extension JackpotRules {

    /// Who a Jackpot leaves standing at the end of a round.
    ///
    /// A Jackpot wins outright, but the opponent always finishes the round
    /// first — the Equalizer. If both jackpot in the same round the two
    /// cancel and play continues, which happens about 0.19% of rounds.
    /// Returns nil when nobody jackpotted, or when they cancelled out.
    static func jackpotWinners(_ jackpotters: [String]) -> [String]? {
        switch jackpotters.count {
        case 0:  return nil
        case 1:  return jackpotters
        default: return nil   // cancelled
        }
    }
}

// MARK: - The pool

extension JackpotRules {

    /// A fresh set of dice, one colourway each.
    ///
    /// Colours come from a shuffled palette rather than being fixed per die
    /// type, so the five are always easy to tell apart on the table.
    static func makeDice() -> [Die] {
        var colorways = DiePalette.colorways.shuffled()
        return dieSides.compactMap { sides in
            guard !colorways.isEmpty else { return nil }
            return Die(sides: sides, colorway: colorways.removeLast())
        }
    }
}

// MARK: - Suite entry

enum JackpotGame: SuiteGame {
    static let floorMotif = FloorMotif.seven
    static let id = "jackpot"
    static let displayName = "Jackpot"
    static let tagline = "Five rounds, or hit the jackpot."

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Your Turn",
            body: "Roll all five dice together. Read the three exposed faces of the d4 — every number except the one against the table — plus the top face of the d6, d8, d12 and d20. Seven numbers in all."
        ),
        GameRuleSection(
            title: "Sets",
            body: "For any number appearing two or more times across your seven, score that number multiplied by how many times it appears. Two 4's = 8. A set of three 3's = 9. The d4's three faces are always different, so they can only match the other dice, never each other."
        ),
        GameRuleSection(
            title: "The d20 Booster",
            body: "If the d20 shows 13 or higher, add its face value to your turn score."
        ),
        GameRuleSection(
            title: "Jackpot",
            body: "If you have no sets at all and the d20 shows 12 or lower, you hit the Jackpot — roughly one roll in 23."
        ),
        GameRuleSection(
            title: "Winning",
            body: "A Jackpot wins the game outright, but your opponent always finishes the round first. If they Jackpot in that same round, both are cancelled and play continues. If nobody Jackpots across all five rounds, the highest total wins."
        )
    ]
}
