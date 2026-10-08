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
    /// `setOfFive` shows as "General" and keeps its old spelling as a case.
    ///
    /// The raw value is the wire format: GeneralsCategory is the key type of
    /// GeneralsCard.claims, which is Codable and travels between devices in
    /// a turn. Renaming the case renames the key, and a card sent by one
    /// build would not decode in the other. What a player reads is
    /// `displayName`, and that is what changed.
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
        case .setOfFive:   return "General"
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

/// Generals as it travels in a message.
///
/// The shared scorecard, which is the entire point of the game: twelve
/// categories claimed once each by whoever takes them first. Nothing else
/// in the suite has state this load-bearing — a lost card is a lost match,
/// and both devices must agree on every claim already made.
///
/// `GeneralsCard` was already Codable; what was missing was a state type to
/// put it in, which is why Generals could not be sent while its card could.
///
/// The five dice and the rolls used do not travel: a turn is three rolls on
/// one device and arrives as a claim.
struct GeneralsState: Codable, Equatable {

    /// Who has claimed what, and for how much.
    var card: GeneralsCard = GeneralsCard()

    private enum CodingKeys: String, CodingKey { case card = "c" }

    init(card: GeneralsCard = GeneralsCard()) { self.card = card }
}

// MARK: - Suite entry

enum GeneralsGame: SuiteGame {
    static let id = "generals"
    static let displayName = "Generals"
    static let tagline = "One scorecard. Claim it first."

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "  * Players: 2.\n  * Dice Pool: 5x d6.\n  * Structure: 12 total turns (6 per player) using a single shared scorecard\n    in a snake turn order (P1, P2, P2, P1...)."
        ),
        GameRuleSection(
            title: "Turn Structure",
            body: "  1. Roll all 5 dice.\n  2. Optionally keep any number of dice and re-roll the rest. Max 3 rolls per turn.\n  3. Claim one available category on the shared scorecard to end turn."
        ),
        GameRuleSection(
            title: "Categories & Scoring",
            body: "  Category          Qualification Requirement           Score\n  -----------------------------------------------------------------------------\n  Ones to Sixes     Any dice showing selected face (1-6) Sum of matching dice\n  Set of 3          Three dice of same face             Sum of all 5 dice\n  Set of 4          Four dice of same face              Sum of all 5 dice\n  Packed House      Three of one face + pair of another 25 Points\n  Small Joker       Four sequential faces (1-2-3-4 etc) 30 Points\n  Large Joker       Five sequential faces (1-2-3-4-5)   40 Points\n  General           All five dice showing same face     50 Points"
        ),
        GameRuleSection(
            title: "Zeroing",
            body: "  If a hand does not qualify for an open category (or by choice), a player\n  must select an open category to claim for 0 points, permanently removing it\n  for both players."
        )
    ]
}
