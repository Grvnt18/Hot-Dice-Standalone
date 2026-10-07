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
        // The palette is refilled rather than exhausted. This asked for a
        // die and got nil once the shuffled colourways ran out, which is
        // the pattern that silently dropped five dice from a twenty-die
        // Free Roll pool. Safe here at 5 against 15 colourways — but safe
        // by a margin nobody was watching, which was equally true of Free
        // Roll while its cap was 10.
        var colorways: [DieColorway] = []
        return (0..<diceCount).map { _ in
            if colorways.isEmpty { colorways = DiePalette.colorways.shuffled() }
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

/// Three Thousand as it travels in a message.
///
/// The turn total rides along for the same reason HOG's does: a turn can be
/// handed over mid-push, and what is at risk is the whole decision.
///
/// The two end-game fields are the ones that would be easy to leave out and
/// expensive to miss. Reaching 3,000 does not end the match — every other
/// player gets one more turn — so the countdown and who got there first
/// both have to cross. Without them the receiving device would either end
/// the match early or never end it.
///
/// The dice on the table do not travel. A turn is resolved where it is
/// played and arrives as points.
struct ThreeThousandState: Codable, Equatable {

    /// Set aside this turn and not yet banked.
    var turnTotal: Int = 0

    /// Turns still owed before the match is decided, once someone has
    /// passed the target. Nil while nobody has.
    var turnsLeftAfterTarget: Int? = nil

    /// Who reached the target first, which is who a tie goes to.
    var firstToTarget: String? = nil

    private enum CodingKeys: String, CodingKey {
        case turnTotal = "t"
        case turnsLeftAfterTarget = "l"
        case firstToTarget = "f"
    }

    init(turnTotal: Int = 0,
         turnsLeftAfterTarget: Int? = nil,
         firstToTarget: String? = nil) {
        self.turnTotal = turnTotal
        self.turnsLeftAfterTarget = turnsLeftAfterTarget
        self.firstToTarget = firstToTarget
    }
}

// MARK: - Suite entry

enum ThreeThousandGame: SuiteGame {
    static let id = "three_thousand"
    static let displayName = "Three Thousand"
    static let tagline = "Bank it or lose it."

    /// Two or more, per GAME_RULES.txt. The turns alternate and the state
    /// is per seat, so nothing here is counting to two — see
    /// TurnMatch.local(playerCount:).
    static let maxPlayers = Int.max


    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "Two or more players, alternating turns. The dice pool is six d6. The first player to reach or exceed 3,000 points wins."
        ),
        GameRuleSection(
            title: "Turn Mechanics",
            body: "Roll all active dice. Set aside at least one scoring die or valid scoring combination — every set-aside die must contribute to a valid score. Then choose to bank the accumulated points, ending the turn, or roll the remaining dice."
        ),
        GameRuleSection(
            title: "Scoring Combinations",
            body: "A single 1 is 100 and a single 5 is 50. Three 1s are 1,000, and three of a kind of 2s to 6s is the face value x 100. Four of a kind is 1,000, five of a kind 2,000 and six of a kind 3,000. A full straight of 1-2-3-4-5-6 is 1,500, and three pairs are 750."
        ),
        GameRuleSection(
            title: "Turn Rules",
            body: "Busted: roll zero scoring dice and the turn ends immediately, with the turn points lost. Hot Dice: set aside all 6 dice into scoring combinations and re-roll all 6 dice to continue accumulating points in the same turn. Match End: when a player reaches 3,000 points, all other players receive one final turn in the round to attempt to beat the highest score."
        )
    ]
}
