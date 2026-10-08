import Foundation

// MARK: - Die color palette

/// 15 unique (body color, number color) pairs, one permanently assigned per
/// physical die. Body colors come from a specific, requested palette —
/// https://javier.xyz/cohesive-colors — 15 source colors run through that
/// tool's "overlay" blend (base color combined with #FF9C00 via a
/// multiply+screen Overlay blend, then lerped 30% toward that blended
/// result) for a cohesive, unified feel across the whole set. Computed
/// directly (verified the tool's underlying colorblendjs algorithm rather
/// than eyeballing it) since the tool itself is client-side JS with no
/// server-side API to call. Number colors are computed per-body-color for
/// WCAG relative luminance contrast (dark text on light bodies, light text
/// on dark bodies) — no longer manually curated per swatch, since the
/// specific body colors are now fixed by the requested palette rather than
/// freely chosen.
struct DieColorway: Codable, Equatable {
    let bodyHex: String

    /// The numeral's ink, DERIVED from the body rather than stored.
    ///
    /// It used to be a second hex typed beside the first, and nothing
    /// checked the pair. Six of the fifteen colourways failed WCAG AA as a
    /// result and five of those were plain backwards — teal `#00ADB4` and
    /// rose `#CB7D94` carried white at 2.52:1 and 2.79:1 where the dark ink
    /// gives 6.26:1 and 5.66:1.
    ///
    /// So it is computed: whichever of the two inks has more contrast
    /// against this body wins. That makes "white numerals on a very dark
    /// die" true by construction rather than by diligence — white always
    /// wins on a dark body — and it cannot drift when a colourway is added.
    ///
    /// `#DB362C` is the one body neither ink clears 4.5:1 on; white takes
    /// it at 4.21:1. These are large numerals, where 3:1 is the bar, and
    /// every pairing clears that comfortably. tools_dice_verify.py asserts
    /// both thresholds.
    var numberHex: String {
        DiePalette.ink(on: bodyHex)
    }

    init(bodyHex: String) {
        self.bodyHex = bodyHex
    }

    /// Only `bodyHex` travels; the ink is recomputed on arrival.
    private enum CodingKeys: String, CodingKey {
        case bodyHex = "b"
    }
}

enum DiePalette {

    /// The two inks a numeral is ever drawn in.
    static let lightInk = "#F5F5F5"
    static let darkInk = "#1B1B1B"

    /// Whichever ink reads better on this body.
    static func ink(on bodyHex: String) -> String {
        contrast(bodyHex, lightInk) >= contrast(bodyHex, darkInk)
            ? lightInk
            : darkInk
    }

    /// WCAG relative luminance, the same formula AppTheme uses to decide
    /// black-or-white text on the accent colour. One rule for ink on a
    /// colour, in two places that both needed it.
    static func relativeLuminance(_ hex: String) -> Double {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var channels: [Double] = []
        for offset in stride(from: 0, to: 6, by: 2) {
            let start = value.index(value.startIndex, offsetBy: offset)
            let end = value.index(start, offsetBy: 2)
            let byte = Int(value[start..<end], radix: 16) ?? 0
            let raw = Double(byte) / 255.0
            channels.append(raw <= 0.03928
                            ? raw / 12.92
                            : pow((raw + 0.055) / 1.055, 2.4))
        }
        guard channels.count == 3 else { return 0 }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    /// WCAG contrast ratio between two hex colours.
    static func contrast(_ one: String, _ other: String) -> Double {
        let a = relativeLuminance(one)
        let b = relativeLuminance(other)
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static let colorways: [DieColorway] = [
        DieColorway(bodyHex: "#6E6456"),
        DieColorway(bodyHex: "#CCDB48"),
        DieColorway(bodyHex: "#CB7D94"),
        DieColorway(bodyHex: "#9A593A"),
        DieColorway(bodyHex: "#FDE558"),
        DieColorway(bodyHex: "#A1CFDD"),
        DieColorway(bodyHex: "#DB362C"),
        DieColorway(bodyHex: "#FFA23F"),
        DieColorway(bodyHex: "#D33AFD"),
        DieColorway(bodyHex: "#7CBD7B"),
        DieColorway(bodyHex: "#A88E65"),
        DieColorway(bodyHex: "#D2735F"),
        DieColorway(bodyHex: "#FBD365"),
        DieColorway(bodyHex: "#FCFBF9"),
        DieColorway(bodyHex: "#00ADB4")
    ]
}

// MARK: - Die

struct Die: Codable, Identifiable, Equatable {
    // Declared without an initial value, and assigned in the init below.
    //
    // It used to read `let id: UUID = UUID()`. That compiles, but a `let`
    // carrying its own initial value is silently skipped by any synthesized
    // decoder — the property cannot be written to, so a decoded Die would
    // quietly get a brand-new id instead of the one that was encoded. Since
    // ids are what `setValue(for:)` and `bank(dieIDs:)` match on, that would
    // have made a received round un-actionable in a way that produced no
    // error, just dice that could never be selected. Taking the default into
    // the init keeps every existing `Die(sides:colorway:)` call site working
    // while making the property genuinely round-trippable.
    let id: UUID
    let sides: Int              // 6, 8, 10, or 12
    let colorway: DieColorway   // permanent, unique per physical die
    var currentValue: Int?      // nil until settled — now set from the physically-landed face, see DiceGameRound.setValue(for:value:)

    init(id: UUID = UUID(), sides: Int, colorway: DieColorway, currentValue: Int? = nil) {
        self.id = id
        self.sides = sides
        self.colorway = colorway
        self.currentValue = currentValue
    }

    /// Points scored if this die is banked right now.
    /// Rolling the max face = 0 pts, each face below that = +1.
    var pointValue: Int? {
        guard let value = currentValue else { return nil }
        // Rolling the maximum face scores 0; every face below it scores
        // more. A 1 is special-cased to the die's own maximum rather than
        // sides - 1, so it's the single worst result you can take on any
        // die — a 1 on a d12 costs 12, not 11.
        return value == 1 ? sides : sides - value
    }
}

// MARK: - Game State

/// Conforms to `Codable` so a round in progress can be written to disk and
/// restored.
///
/// This is not for sending — a finished round travels as `RollsPlayerResult`,
/// which is far smaller. It is for surviving termination. A Messages
/// extension runs under much tighter memory limits than an app and is killed
/// aggressively when the user switches away; without this, tapping out of
/// Messages part-way through banking dice would silently lose the round.
///
/// Written out rather than synthesized because the compiler's synthesis
/// rules for classes are easy to trip over (and there is no way to
/// compile-check that here), and because being explicit means the encoded
/// shape only changes when someone deliberately changes it.
final class DiceGameRound: Codable {

    private(set) var pool: [Die]

    /// The full 15-die pool as it was dealt, kept after `pool` starts
    /// shrinking. Payload encoding needs it: dice travel as indices into the
    /// dealt order, and by the time a round is finished `pool` is empty.
    /// Rebuilding it from the seed would give the right sides and colorways
    /// but fresh UUIDs, so it would no longer match the banked dice by id.
    private(set) var originalPool: [Die]

    private(set) var bankedScore: Int = 0
    private(set) var hasRolledThisTurn: Bool = false

    /// Dice in the order they were banked, for the 3x5 history grid.
    /// Each entry's colorway ties back to DiePalette so a specific physical
    /// die can be traced across the grid regardless of its sides/type.
    private(set) var bankedOrder: [Die] = []

    /// The seed this round was built from, carried so the pool's makeup can
    /// be reproduced on the receiving device.
    ///
    /// Note this seeds the *pool*, not the results: Rolls reads each die's
    /// value from whichever face physically lands up, and SceneKit physics
    /// is not reproducible across devices. See `SeededGenerator`'s note.
    let seed: UInt64

    init(seed: UInt64 = SeededGenerator.newSeed()) {
        self.seed = seed
        var rng = SeededGenerator(seed: seed)

        // 12 D6, 1 D8, 1 D10, 1 D12 = 15 dice total, each given a unique
        // permanent colorway from the 15-entry palette.
        let colorways = rng.shuffled(DiePalette.colorways)

        // Shuffled so colorway assignment isn't correlated with die type.
        let sideCounts = rng.shuffled(Array(repeating: 6, count: 12) + [8, 10, 12])

        let dealt = zip(sideCounts, colorways).map { sides, colorway in
            Die(sides: sides, colorway: colorway)
        }
        self.pool = dealt
        self.originalPool = dealt
    }

    private enum CodingKeys: String, CodingKey {
        case seed, pool, originalPool, bankedScore, hasRolledThisTurn, bankedOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seed = try c.decode(UInt64.self, forKey: .seed)
        pool = try c.decode([Die].self, forKey: .pool)
        originalPool = try c.decode([Die].self, forKey: .originalPool)
        bankedScore = try c.decode(Int.self, forKey: .bankedScore)
        hasRolledThisTurn = try c.decode(Bool.self, forKey: .hasRolledThisTurn)
        bankedOrder = try c.decode([Die].self, forKey: .bankedOrder)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seed, forKey: .seed)
        try c.encode(pool, forKey: .pool)
        try c.encode(originalPool, forKey: .originalPool)
        try c.encode(bankedScore, forKey: .bankedScore)
        try c.encode(hasRolledThisTurn, forKey: .hasRolledThisTurn)
        try c.encode(bankedOrder, forKey: .bankedOrder)
    }

    var isGameOver: Bool {
        pool.isEmpty
    }

    /// Marks a new roll as in progress. Values are no longer pre-randomized
    /// here — per your latest design change, the true result now comes
    /// from whichever face physically lands up (read via
    /// setValue(for:value:), called once each die's settle/face-snap
    /// completes). This just flips the "a roll has started" flag that
    /// gates the Roll button / selection UI; currentValue for each die
    /// stays nil until physics actually determines it.
    func rollPool() {
        guard !isGameOver else { return }
        hasRolledThisTurn = true
    }

    /// Called once a die has physically settled and face-snapped — writes
    /// the value read from whichever face landed up as this die's true
    /// scored result.
    func setValue(for dieID: UUID, value: Int) {
        guard let index = pool.firstIndex(where: { $0.id == dieID }) else { return }
        pool[index].currentValue = value
    }

    /// Bank one or more dice from the current roll for score, removing them from the pool.
    /// Enforces the "must bank at least 1 die per roll" rule at the call site —
    /// the UI should require selectedIDs.count >= 1 before allowing a re-roll.
    @discardableResult
    func bank(dieIDs: Set<UUID>) -> Int {
        guard hasRolledThisTurn, !dieIDs.isEmpty else { return 0 }

        let toBank = pool.filter { dieIDs.contains($0.id) && $0.currentValue != nil }
        let points = toBank.compactMap { $0.pointValue }.reduce(0, +)

        pool.removeAll { dieIDs.contains($0.id) }
        bankedOrder.append(contentsOf: toBank) // preserves banking order for the grid
        bankedScore += points
        hasRolledThisTurn = false // must reroll remaining pool before banking again

        return points
    }
}
