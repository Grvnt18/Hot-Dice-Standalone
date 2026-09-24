import Foundation

/// Three Thousand: six dice, set aside what scores, and decide every single
/// roll whether to push on or bank.
///
/// The target sets the name. At 3,000 a match runs about twelve messages,
/// half of all turns bust to nothing, and a banked turn averages around
/// 900 — so one good turn is a third of the game and a bad one costs you
/// everything you had built.
enum ThreeThousandRules {

    /// Bank this and the opponent gets one last turn to beat it.
    static let target = 3000

    /// Six identical d6. The scoring table is built on a shared six-value
    /// space — the straight, the three pairs and the triplets all depend on
    /// it — which is why no polyhedral die belongs in this game.
    static let diceCount = 6

    /// A fresh set, one colourway each, so a die you set aside stays
    /// tellable from the ones still in play.
    static func makeDice() -> [Die] {
        var colorways = DiePalette.colorways.shuffled()
        return (0..<diceCount).compactMap { _ in
            guard !colorways.isEmpty else { return nil }
            return Die(sides: 6, colorway: colorways.removeLast())
        }
    }
}

// MARK: - Scoring

extension ThreeThousandRules {

    static let straightPoints = 1500
    static let threePairPoints = 750
    static let fourOfAKindPoints = 1000
    static let fiveOfAKindPoints = 2000
    static let sixOfAKindPoints = 3000

    /// What a set of dice is worth — or nil if it is not a legal set-aside.
    ///
    /// **The nil is the important half.** A set-aside is legal only when
    /// every die in it takes part in a scoring combination: you may keep a
    /// single 1, but you may not smuggle a 2 out alongside it. Returning
    /// nil rather than silently scoring the 1 is what lets the screen grey
    /// out Roll On and Bank instead of quietly stealing a die.
    ///
    /// Combinations are consumed in order — straight, three pairs, then
    /// n-of-a-kind for n ≥ 3, then loose 1's and 5's. Anything still
    /// unconsumed means the set was not legal.
    static func score(faces: [Int]) -> Int? {
        guard !faces.isEmpty else { return nil }

        var counts: [Int: Int] = [:]
        for face in faces { counts[face, default: 0] += 1 }

        // Both of these use all six dice, so they can only ever apply to a
        // whole fresh roll.
        if faces.count == 6 {
            if counts.count == 6 { return straightPoints }
            if counts.values.allSatisfy({ $0 == 2 }) { return threePairPoints }
        }

        var points = 0
        for (face, count) in counts where count >= 3 {
            switch count {
            case 3:  points += (face == 1) ? 1000 : face * 100
            case 4:  points += fourOfAKindPoints
            case 5:  points += fiveOfAKindPoints
            default: points += sixOfAKindPoints
            }
            counts[face] = 0
        }

        points += (counts[1] ?? 0) * 100 + (counts[5] ?? 0) * 50
        counts[1] = 0
        counts[5] = 0

        // Any die left over never scored, so the whole set-aside is illegal.
        guard counts.values.allSatisfy({ $0 == 0 }) else { return nil }
        return points
    }

    /// Whether a roll contains anything at all worth setting aside.
    ///
    /// A roll with nothing is a Bust, which ends the turn and takes the
    /// running total with it — that is half of all turns.
    static func hasScoringDice(_ faces: [Int]) -> Bool {
        var counts: [Int: Int] = [:]
        for face in faces { counts[face, default: 0] += 1 }
        if counts[1] != nil || counts[5] != nil { return true }
        if counts.values.contains(where: { $0 >= 3 }) { return true }
        if faces.count == 6 {
            if counts.count == 6 { return true }
            if counts.values.allSatisfy({ $0 == 2 }) { return true }
        }
        return false
    }
}

// MARK: - Describing a turn

extension ThreeThousandRules {

    /// One line for the handover screen.
    static func summary(player: String, banked: Int, lost: Int, busted: Bool) -> String {
        if busted {
            return lost > 0
                ? "\(player) busted and lost \(lost)."
                : "\(player) busted on the first roll."
        }
        return "\(player) banked \(banked)."
    }
}

// MARK: - Suite entry

enum ThreeThousandGame: SuiteGame {
    static let floorMotif = FloorMotif.circles
    static let id = "three_thousand"
    static let displayName = "Three Thousand"
    static let tagline = "Bank it or lose it."

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Your Turn",
            body: "Roll all six dice. Tap the dice that score to set them aside — you must set aside at least one, and every die you take has to be part of a scoring combination. Then roll what is left, or bank."
        ),
        GameRuleSection(
            title: "Scoring",
            body: "Each 1 is 100 and each 5 is 50. Three of a kind scores the face times 100 — three 1's are 1,000. Four of a kind is 1,000, five is 2,000, six is 3,000. A 1-2-3-4-5-6 straight is 1,500 and three pairs are 750."
        ),
        GameRuleSection(
            title: "Busted",
            body: "Roll and find nothing that scores and you are Busted: the turn ends and everything you had going that turn is gone. About half of all turns end this way."
        ),
        GameRuleSection(
            title: "Hot Dice",
            body: "Set aside all six and you roll all six again with your running total intact. There is no limit to how far a turn can run — and no safety in it either."
        ),
        GameRuleSection(
            title: "Winning",
            body: "Bank 3,000 and your opponent gets one last turn to beat it. If they cannot, you win — a tie goes to whoever got there first."
        )
    ]
}
