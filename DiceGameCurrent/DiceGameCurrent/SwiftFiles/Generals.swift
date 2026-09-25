import Foundation

/// Generals: poker dice played onto a single shared scorecard.
///
/// Twelve categories, claimed once each by whoever takes them first, so the
/// whole match is twelve turns rather than twenty-six. Taking Large Joker
/// scores you 40 *and* denies it forever, which is the point: every turn
/// reaches across the table.
enum GeneralsRules {

    /// Five identical d6.
    static let diceCount = 5

    /// Rolls per turn, including the first.
    static let rollsPerTurn = 3

    /// The order seats claim in, over the full twelve turns.
    ///
    /// **A snake, not strict alternation, and it was measured.** Over
    /// 60,000 simulated matches with both seats playing the same strategy,
    /// alternation gave the first seat 61.4% of decided matches at a +9.0
    /// mean margin — twelve categories and first pick of all of them is a
    /// structural edge, not noise. The snake gives six claims each and
    /// takes it to 51.0% and +0.7.
    ///
    /// A roll-off for who starts was considered and dropped: it would not
    /// change a 60/40 split, only decide at random who receives it.
    static let snakeOrder = [0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0]

    /// Twelve claims across two players is six rounds of two turns.
    static let roundsPerPlayer = snakeOrder.count / 2

    /// A fresh set: five d6, each its own colourway, so the dice you kept
    /// are still easy to tell apart when only two of them move.
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

// MARK: - Categories

/// One box on the shared card.
///
/// **Gamble and the +35 upper bonus are both dropped**, as approved.
/// Gamble is the one category with no qualifying condition, so on a shared
/// card it is pure cleanup with nothing to race for; the bonus needs 63
/// across six upper categories a player can no longer count on getting, so
/// it would reward whoever happened to be blocked less.
enum GeneralsCategory: String, CaseIterable, Codable, Identifiable {
    case ones, twos, threes, fours, fives, sixes
    case setOfThree, setOfFour, packedHouse
    case smallJoker, largeJoker, setOfFive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ones:        return "Ones"
        case .twos:        return "Twos"
        case .threes:      return "Threes"
        case .fours:       return "Fours"
        case .fives:       return "Fives"
        case .sixes:       return "Sixes"
        case .setOfThree:  return "Set of 3"
        case .setOfFour:   return "Set of 4"
        case .packedHouse: return "Packed House"
        case .smallJoker:  return "Small Joker"
        case .largeJoker:  return "Large Joker"
        case .setOfFive:   return "Set of 5"
        }
    }

    /// What it pays, for the card's second line.
    var detail: String {
        switch self {
        case .ones, .twos, .threes, .fours, .fives, .sixes:
            return "Sum of that number"
        case .setOfThree:  return "3 alike — sum of all five"
        case .setOfFour:   return "4 alike — sum of all five"
        case .packedHouse: return "3 and a pair — 25"
        case .smallJoker:  return "4 in a row — 30"
        case .largeJoker:  return "5 in a row — 40"
        case .setOfFive:   return "5 alike — 50"
        }
    }

    /// The face this counts, for the six upper categories.
    private var upperFace: Int? {
        switch self {
        case .ones:   return 1
        case .twos:   return 2
        case .threes: return 3
        case .fours:  return 4
        case .fives:  return 5
        case .sixes:  return 6
        default:      return nil
        }
    }

    /// What a hand of five faces scores in this box — 0 when it does not
    /// qualify, which is exactly what zeroing writes.
    func score(for faces: [Int]) -> Int {
        var counts: [Int: Int] = [:]
        for face in faces { counts[face, default: 0] += 1 }
        let total = faces.reduce(0, +)
        let best = counts.values.max() ?? 0

        if let face = upperFace {
            return (counts[face] ?? 0) * face
        }

        switch self {
        case .setOfThree:
            return best >= 3 ? total : 0
        case .setOfFour:
            return best >= 4 ? total : 0
        case .packedHouse:
            // Five alike qualifies: it is a three and a pair of the same
            // number, and refusing it would make the best hand in the game
            // worth less in this box than a worse one.
            return (counts.values.sorted() == [2, 3] || best == 5) ? 25 : 0
        case .smallJoker:
            return GeneralsCategory.longestRun(in: counts.keys) >= 4 ? 30 : 0
        case .largeJoker:
            return GeneralsCategory.longestRun(in: counts.keys) >= 5 ? 40 : 0
        case .setOfFive:
            return best == 5 ? 50 : 0
        default:
            return 0
        }
    }

    /// Longest run of consecutive faces present, ignoring duplicates.
    private static func longestRun<S: Sequence>(in faces: S) -> Int where S.Element == Int {
        let present = Set(faces).sorted()
        var longest = 0
        var run = 0
        var previous: Int?
        for face in present {
            if let previous, face == previous + 1 { run += 1 } else { run = 1 }
            previous = face
            longest = max(longest, run)
        }
        return longest
    }
}

// MARK: - The shared card

/// Who has claimed what, and for how much.
///
/// One card for the whole match rather than one each — the entire reason
/// the game is twelve turns and every claim is felt across the table.
struct GeneralsCard: Codable, Equatable {

    struct Claim: Codable, Equatable {
        let participant: String
        let points: Int
    }

    private(set) var claims: [GeneralsCategory: Claim] = [:]

    init() {}

    var openCategories: [GeneralsCategory] {
        GeneralsCategory.allCases.filter { claims[$0] == nil }
    }

    var isComplete: Bool { claims.count == GeneralsCategory.allCases.count }

    func claim(for category: GeneralsCategory) -> Claim? { claims[category] }

    /// Claims a box. Ignores a category already taken, so a double tap on
    /// the card cannot overwrite someone else's claim.
    @discardableResult
    mutating func claim(
        _ category: GeneralsCategory,
        by participant: String,
        points: Int
    ) -> Bool {
        guard claims[category] == nil else { return false }
        claims[category] = Claim(participant: participant, points: points)
        return true
    }

    // Dictionaries keyed by anything but String or Int encode as a flat
    // array, which round-trips but reads badly and drops the key type's
    // meaning. Encoding the raw values keeps the payload legible and keeps
    // the key type free to gain cases later.
    private enum CodingKeys: String, CodingKey { case claims = "c" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: Claim].self, forKey: .claims)
        claims = [:]
        for (key, value) in raw {
            guard let category = GeneralsCategory(rawValue: key) else { continue }
            claims[category] = value
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let raw = Dictionary(uniqueKeysWithValues: claims.map { ($0.key.rawValue, $0.value) })
        try container.encode(raw, forKey: .claims)
    }
}

// MARK: - Describing a turn

extension GeneralsRules {

    /// One line for the handover screen.
    static func summary(
        player: String,
        category: GeneralsCategory,
        points: Int
    ) -> String {
        points > 0
            ? "\(player) took \(category.displayName) for \(points)."
            : "\(player) zeroed \(category.displayName) — and burned it."
    }
}

// MARK: - Suite entry

enum GeneralsGame: SuiteGame {
    static let floorMotif = FloorMotif.stars
    static let id = "generals"
    static let displayName = "Generals"
    static let tagline = "One scorecard. Claim it first."

    /// The short version, shown from inside the game.
    static let quickRules: [GameRuleSection] = [
        GameRuleSection(
            title: "The Goal",
            body: "One shared card of twelve categories, claimed once each by whoever takes it first. Six claims apiece, twelve turns in all, highest total wins."
        ),
        GameRuleSection(
            title: "Your Turn",
            body: "Roll five dice, tap the ones to keep, roll the rest — three rolls — then claim one open category for whatever your hand pays there."
        ),
        GameRuleSection(
            title: "Zeroing",
            body: "If nothing qualifies you must still claim a category, for zero. It burns that category for your opponent too."
        )
    ]

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "One Card, Two Players",
            body: "There are twelve categories and a single shared scorecard. Each category can be claimed once, by whoever takes it first — so the whole game is twelve turns, six each."
        ),
        GameRuleSection(
            title: "Your Turn",
            body: "Roll five dice. Tap any dice you want to keep, then roll the rest — up to three rolls in all. Then claim one open category for whatever your hand scores in it."
        ),
        GameRuleSection(
            title: "The Categories",
            body: "Ones through Sixes score the sum of that number and nothing else. Set of 3 needs three dice on the same face and Set of 4 needs four, and both score all five dice added up. Packed House is three of one and a pair of another, for 25. Small Joker is four consecutive faces — 1-2-3-4, 2-3-4-5 or 3-4-5-6 — for 30. Large Joker is five consecutive, 1-2-3-4-5 or 2-3-4-5-6, for 40. Set of 5 is all five on the same face, for 50."
        ),
        GameRuleSection(
            title: "Zeroing",
            body: "If nothing you rolled qualifies, you must still claim a category — for zero. That burns it for your opponent too, so which one you give up is a real decision."
        ),
        GameRuleSection(
            title: "Turn Order",
            body: "Turns run in a snake: you, them, them, you, you, them, and so on. Six claims each. Going first on a shared card is otherwise worth about ten points, and the snake is what takes that away."
        ),
        GameRuleSection(
            title: "Winning",
            body: "The game ends when all twelve categories are claimed. Highest total wins."
        )
    ]
}
