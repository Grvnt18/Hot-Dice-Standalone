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
        // Refilled rather than exhausted — see FreeRollPool.makeDice for
        // the bug this shape caused there. Five dice against 15 colourways
        // is safe today; it was safe in Free Roll too, until the cap moved.
        var colorways: [DieColorway] = []
        return dieSides.map { sides in
            if colorways.isEmpty { colorways = DiePalette.colorways.shuffled() }
            return Die(sides: sides, colorway: colorways.removeLast())
        }
    }
}

/// Jackpot as it travels in a message.
///
/// The round's unresolved Jackpots. They cannot be settled when they are
/// rolled — a Jackpot only wins once everyone else in the round has had
/// their turn, and two in the same round cancel — so the list has to
/// survive the handover or the Equalizer silently stops working.
///
/// Scores live in `TurnMatch`, and the five dice are re-read from the seed,
/// so this is the whole of what Jackpot adds to the wire.
struct JackpotState: Codable, Equatable {

    /// Participants who have hit a Jackpot in the round now being played.
    var jackpotsThisRound: [String] = []

    private enum CodingKeys: String, CodingKey { case jackpotsThisRound = "j" }

    init(jackpotsThisRound: [String] = []) {
        self.jackpotsThisRound = jackpotsThisRound
    }
}

// MARK: - Suite entry

enum JackpotGame: SuiteGame {
    static let id = "jackpot"
    static let displayName = "Jackpot"
    static let tagline = "Five rounds, or hit the jackpot."

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "  * Players: 2 (alternating turns across 5 rounds).\n  * Dice Pool: 1x d4, 1x d6, 1x d8, 1x d12, 1x d20.\n  * Objective: Accumulate highest total points or trigger instant-win Jackpot."
        ),
        GameRuleSection(
            title: "Reading the Roll",
            body: "  Each roll yields seven numbers:\n    * The 3 exposed side faces of the d4.\n    * The top face of the d6, d8, d12, and d20."
        ),
        GameRuleSection(
            title: "Scoring & Instant Win Conditions",
            body: "  * Sets: Any number appearing two or more times among the 7 exposed values scores:\n      Score = Number Value x Occurrences\n  * Booster: A d20 showing 13 or higher adds its raw face value to turn score.\n  * Jackpot (Instant Win): Achieved when there are ZERO sets across all 7 numbers\n    AND the d20 shows 12 or lower."
        ),
        GameRuleSection(
            title: "Match Resolution",
            body: "  * An uncancelled Jackpot wins the match instantly.\n  * If a player rolls a Jackpot, all other players in the round complete their final\n    turn. If multiple players hit a Jackpot in the same round, they cancel\n    out and play continues.\n  * If no Jackpot is hit after 5 rounds, the highest total score wins."
        )
    ]
}
