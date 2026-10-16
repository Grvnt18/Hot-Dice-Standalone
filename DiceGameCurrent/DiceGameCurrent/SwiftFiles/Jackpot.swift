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

    // MARK: The Big 7

    /// Three 7s pay a flat 77 INSTEAD of the set's own score.
    ///
    /// Only three dice in the pool can show a 7 at all — the d8, the d12
    /// and the d20 — so this is every one of them landing on the same
    /// face, and the d4 and d6 cannot help. That is 1 in 1,920 rolls.
    /// Scored normally it would be 7 x 3 = 21, which is less than a pair
    /// of 11s; 77 makes the rarest thing on the table worth noticing.
    static let bigSevenValue = 7
    static let bigSevenCount = 3
    static let bigSevenBonus = 77

    // MARK: The Escalation

    /// What a set formed on the re-roll is worth.
    static let escalationMultiplier = 2
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

    /// What each die showed, as a line: "d4 2·3·4   d6 5   d8 1   d12 9   d20 17".
    ///
    /// Jackpot scores SEVEN numbers off five dice, and which seven is the
    /// one thing the table cannot be asked. The d4 contributes three — the
    /// faces that are not against the floor — so two of its numbers are on
    /// the far side of the die from wherever the player is sitting, and
    /// the summary line only ever named the sets that paid. A player who
    /// wanted to know why a roll scored what it scored had to take the
    /// score's word for it.
    ///
    /// Built from `numbers(from:)`'s own reading rather than a second one,
    /// so the line cannot say something the scoring disagrees with — the
    /// d4 especially, where `value` is a resting face and not a number
    /// anybody can see.
    ///
    /// Sorted by die rather than left in settle order: the dice land in a
    /// different order every throw, and a readout that reshuffles itself
    /// each time is one the eye has to re-read from scratch.
    static func readout(from results: [DiceTraySession.DieResult]) -> String {
        results.sorted { $0.sides < $1.sides }.map { result in
            let faces = numbers(from: [result])
            return "d\(result.sides) "
                + faces.map(String.init).joined(separator: "·")
        }
        .joined(separator: "   ")
    }
}

// MARK: - Scoring

extension JackpotRules {

    struct TurnScore: Equatable {
        /// Points from matching sets, with the escalation's multiplier
        /// already applied to anything formed on a re-roll.
        let setPoints: Int
        /// The d20's face, if it boosted.
        let booster: Int?
        /// True when the roll had no sets and a low d20.
        let isJackpot: Bool
        /// What the sets were, for the turn summary: value and how many.
        /// A Big 7 is NOT in here — it pays its own bonus instead.
        let sets: [(value: Int, count: Int)]
        /// Three 7s among the seven numbers.
        let hasBigSeven: Bool
        /// An escalation that formed no set at all. Everything the turn
        /// had, locked points included, goes with it.
        let isWipeout: Bool

        var total: Int {
            if isWipeout { return 0 }
            return setPoints + (booster ?? 0) + (hasBigSeven ? bigSevenBonus : 0)
        }

        static func == (lhs: TurnScore, rhs: TurnScore) -> Bool {
            lhs.setPoints == rhs.setPoints
                && lhs.booster == rhs.booster
                && lhs.isJackpot == rhs.isJackpot
                && lhs.hasBigSeven == rhs.hasBigSeven
                && lhs.isWipeout == rhs.isWipeout
                && lhs.sets.map(\.value) == rhs.sets.map(\.value)
                && lhs.sets.map(\.count) == rhs.sets.map(\.count)
        }
    }

    /// The sets in a handful of numbers, biggest first.
    ///
    /// Sorted for a stable, readable summary — dictionary order is not
    /// stable, and the same roll should always describe itself the same
    /// way. The order is also what `lockedSet` reads: biggest set first
    /// means the first entry is the one the escalation locks.
    static func sets(in numbers: [Int]) -> [(value: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for number in numbers { counts[number, default: 0] += 1 }
        return counts
            .filter { $0.value >= 2 }
            .map { (value: $0.key, count: $0.value) }
            .sorted { ($0.count, $0.value) > ($1.count, $1.value) }
    }

    /// Whether these numbers carry the Big 7.
    static func hasBigSeven(_ numbers: [Int]) -> Bool {
        numbers.filter { $0 == bigSevenValue }.count >= bigSevenCount
    }

    /// Scores one roll.
    ///
    /// A set is any number appearing twice or more across the seven, and it
    /// scores that number times how many times it appears — two 4s is 8, a
    /// set of three 3s is 9.
    static func score(numbers: [Int], d20: Int?) -> TurnScore {
        let found = sets(in: numbers)
        let big = hasBigSeven(numbers)

        // The Big 7's own set does not also score. "In place of", not "as
        // well as": three 7s scored both ways would be 98, and the bonus
        // is meant to replace a set worth 21, not to sit on top of it.
        let scoring = big ? found.filter { $0.value != bigSevenValue } : found

        return TurnScore(
            setPoints: scoring.reduce(0) { $0 + $1.value * $1.count },
            booster: booster(forD20: d20),
            // A roll with no set at all and a low d20. Unchanged by the
            // escalation: a turn with nothing to lock has nothing to
            // escalate, so the two can never be offered together.
            isJackpot: found.isEmpty && (d20 ?? 0) <= jackpotThreshold,
            sets: scoring,
            hasBigSeven: big,
            isWipeout: false
        )
    }

    private static func booster(forD20 d20: Int?) -> Int? {
        guard let d20, d20 >= boosterThreshold else { return nil }
        return d20
    }

    /// The set an escalation would lock: the biggest one.
    ///
    /// `sets(in:)` is sorted by count then value, so the first entry is
    /// the highest-scoring one — and ties break toward the bigger number,
    /// which is the one worth keeping.
    static func lockedSet(in numbers: [Int]) -> (value: Int, count: Int)? {
        sets(in: numbers).first
    }

    /// Whether this roll offers the choice at all.
    ///
    /// A Jackpot is excluded even though it cannot have sets, because a
    /// Jackpot has already won the turn and nothing should invite a player
    /// to gamble it away.
    static func canEscalate(_ score: TurnScore) -> Bool {
        !score.isJackpot && !score.sets.isEmpty
    }

    /// The score for a turn that escalated.
    ///
    /// `lockedNumbers` are the ones held — every face of every die that
    /// stayed on the table — and `rerolled` are the numbers the re-roll
    /// produced. The locked points are the locked set scored once, at its
    /// own value; anything the re-roll forms is scored at
    /// `escalationMultiplier` and added.
    ///
    /// And if the re-roll forms nothing, the turn is a wipeout: not the
    /// re-roll's points, the TURN's, locked set included. That is the
    /// whole shape of the gamble, and it is why `isWipeout` lives on the
    /// score rather than being handled by the screen — a total that
    /// quietly keeps the locked points would be the kindest possible bug
    /// and nobody would report it.
    static func escalatedScore(lockedNumbers: [Int],
                               rerolled: [Int],
                               d20: Int?) -> TurnScore {
        let locked = sets(in: lockedNumbers)
        let fresh = sets(in: rerolled)
        let big = hasBigSeven(lockedNumbers + rerolled)

        let lockedScoring = big ? locked.filter { $0.value != bigSevenValue } : locked
        let freshScoring = big ? fresh.filter { $0.value != bigSevenValue } : fresh

        let points = lockedScoring.reduce(0) { $0 + $1.value * $1.count }
            + freshScoring.reduce(0) { $0 + $1.value * $1.count } * escalationMultiplier

        return TurnScore(
            setPoints: points,
            booster: booster(forD20: d20),
            // An escalation cannot jackpot. It started from a roll that
            // had a set, and the Jackpot is the absence of one.
            isJackpot: false,
            sets: lockedScoring + freshScoring,
            hasBigSeven: big,
            isWipeout: fresh.isEmpty
        )
    }

    /// One line describing what a turn did, for the handover screen.
    static func summary(for score: TurnScore, player: String) -> String {
        if score.isJackpot { return "\(player) hit the Jackpot!" }
        if score.isWipeout { return "\(player) escalated into nothing — wiped out." }
        var parts: [String] = []
        if score.hasBigSeven { parts.append("the Big 7") }
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

    /// Which dice an escalation holds: every one showing a number from the
    /// locked set.
    ///
    /// The d4 is held on ANY of its three exposed faces, which is the rule
    /// the guide states and the one that needed stating — a d4 is three of
    /// the seven numbers, so "the dice in the set" is ambiguous for it in
    /// a way it is not for the others.
    ///
    /// Reads each die through `numbers(from:)`, so a d4's resting face is
    /// never mistaken for a number on show.
    static func lockedDice(_ results: [DiceTraySession.DieResult],
                           setValue: Int) -> Set<UUID> {
        var held: Set<UUID> = []
        for result in results where numbers(from: [result]).contains(setValue) {
            held.insert(result.id)
        }
        return held
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
            body: "  * Sets: Any number appearing two or more times among the 7 exposed values scores:\n      Score = Number Value x Occurrences\n  * Booster: A d20 showing 13 or higher adds its raw face value to turn score.\n  * Jackpot (Instant Win): Achieved when there are ZERO sets across all 7 numbers\n    AND the d20 shows 12 or lower.\n  * Big 7 Bonus: Three 7s among the seven numbers — the d8, d12 and d20 all\n    showing 7 — pay a flat 77 points in place of that set's normal score."
        ),
        GameRuleSection(
            title: "The Escalation",
            body: "  * After a roll that forms at least one set, the turn offers a choice:\n      Bank: take the turn as rolled and pass.\n      Escalate: lock the highest-scoring set and re-roll everything else.\n  * Locking: every die showing a number from that set is held, including the\n    d4 if any of its three exposed faces belongs to it.\n  * The Multiplier: sets formed among the re-rolled numbers score DOUBLE, and\n    are added to the locked points.\n  * Wipeout: if the re-roll forms no set at all, the whole turn scores zero —\n    the locked points go with it.\n  * One escalation per turn. The booster is read from the d20's final face, and\n    the Big 7 Bonus from the seven numbers as they finally stand."
        ),
        GameRuleSection(
            title: "Match Resolution",
            body: "  * An uncancelled Jackpot wins the match instantly.\n  * If a player rolls a Jackpot, all other players in the round complete their final\n    turn. If multiple players hit a Jackpot in the same round, they cancel\n    out and play continues.\n  * If no Jackpot is hit after 5 rounds, the highest total score wins."
        )
    ]
}
