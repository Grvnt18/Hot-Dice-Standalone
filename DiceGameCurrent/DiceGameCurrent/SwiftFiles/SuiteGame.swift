import SwiftUI

/// What every game in the suite has to provide for the hub to list it, the
/// rules sheet to explain it, and (later) the Messages extension to send it.
///
/// **Deliberately N-player, even though seven of the eight are two-player.**
/// Rolls is a single round with no turn order, so it works in a group chat
/// as well as one-to-one — everyone rolls once and the lowest score wins.
/// Modelling participants as a keyed collection now costs nothing; adding it
/// later would mean touching every game that had baked in a
/// `player1`/`player2` pair. `maxPlayers` is what each game uses to
/// constrain itself.
protocol SuiteGame {

    /// Stable identifier. Travels in the message payload, so **changing it
    /// breaks games already in flight** — treat it as permanent once shipped.
    static var id: String { get }

    /// Name as it appears on the hub tile and the rules sheet.
    static var displayName: String { get }

    /// One-line pitch for the tile, under the name.
    static var tagline: String { get }

    /// Rules, one paragraph per entry, for the How to Play sheet.
    static var rules: [String] { get }

    /// Upper bound on participants. Two for everything except Rolls, which
    /// has no ceiling beyond what a group chat contains.
    static var maxPlayers: Int { get }

    /// Whether the lowest score wins.
    ///
    /// Rolls is golf-scored — its points are penalties, so 0 is perfect.
    /// Every other game in the suite is higher-is-better. Shared result UI
    /// reads this rather than assuming, which is what `TurnCompleteOverlay`
    /// got wrong when it was written for Rolls alone.
    static var lowestScoreWins: Bool { get }

    /// Whether a turn can be sent to someone else.
    ///
    /// False only for Free Roll, which is a solo sandbox with no opponent
    /// state — it has nothing to put in a message. Every other game is
    /// sendable, and the hub uses this to decide what to show inside a
    /// Messages conversation versus the full app.
    static var isSendable: Bool { get }
}

extension SuiteGame {
    // Sensible defaults: two players, high score wins, sendable. A game only
    // states what makes it unusual.
    static var maxPlayers: Int { 2 }
    static var lowestScoreWins: Bool { false }
    static var isSendable: Bool { true }
}

// MARK: - The catalogue

/// Every game in the suite, in hub order.
///
/// Type-erased into a description rather than an array of metatypes: the hub
/// only needs to render a tile and know whether it can be opened, and the
/// six unbuilt games have no type to point at yet. They are still listed —
/// showing them greyed out is more honest than pretending the suite is two
/// games, and it sets the expectation of what is coming.
///
struct GameCatalogEntry: Identifiable {
    let id: String
    let displayName: String
    let tagline: String
    let isAvailable: Bool

    /// Builds the game's root view, given the action that returns to the
    /// hub. Nil for anything not yet implemented.
    ///
    /// The dismissal is passed *in* rather than the game reaching for an
    /// environment dismiss: games are presented full screen precisely so
    /// they keep the whole display, which means there is no navigation
    /// chrome to go back with — each game draws its own control.
    let makeView: ((@escaping () -> Void) -> AnyView)?

    init(
        id: String,
        displayName: String,
        tagline: String,
        makeView: ((@escaping () -> Void) -> AnyView)? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.tagline = tagline
        self.isAvailable = makeView != nil
        self.makeView = makeView
    }

    /// Convenience for a game that conforms to `SuiteGame`, so its metadata
    /// is stated once in the game itself rather than duplicated here.
    init<G: SuiteGame>(
        _ game: G.Type,
        makeView: @escaping (@escaping () -> Void) -> AnyView
    ) {
        self.init(
            id: G.id,
            displayName: G.displayName,
            tagline: G.tagline,
            makeView: makeView
        )
    }
}

enum GameCatalog {

    /// Hub order. Rolls and Free Roll open; the rest render as "Soon"
    /// tiles until each is built, in the order listed here.
    static let all: [GameCatalogEntry] = [
        GameCatalogEntry(RollsGame.self) { onExit in
            AnyView(DiceGameScreen(onExit: onExit))
        },
        GameCatalogEntry(FreeRollGame.self) { onExit in
            AnyView(FreeRollScreen(onExit: onExit))
        },
        GameCatalogEntry(id: "chasing6", displayName: "Chasing 6",
                         tagline: "Five rounds, or hit the jackpot."),
        GameCatalogEntry(id: "pig", displayName: "Pig",
                         tagline: "Push your luck to 75."),
        GameCatalogEntry(id: "generals", displayName: "Generals",
                         tagline: "One scorecard. Claim it first."),
        GameCatalogEntry(id: "three_thousand", displayName: "Three Thousand",
                         tagline: "Bank it or lose it."),
        GameCatalogEntry(id: "nautical654", displayName: "Nautical 6-5-4",
                         tagline: "Ship, captain, crew. Best of three."),
        GameCatalogEntry(id: "royal_path", displayName: "The Royal Path",
                         tagline: "Race, capture, come home.")
    ]
}

// MARK: - Rolls

/// Rolls' entry in the suite. The game itself is unchanged — this only
/// declares what the hub and rules sheet need to know about it.
enum RollsGame: SuiteGame {
    static let id = RollsGameState.gameID
    static let displayName = "Rolls"
    static let tagline = "One round. Lowest score takes it."

    /// The only game with no player ceiling: a single round has no turn
    /// order, so a whole group chat can play at once.
    static let maxPlayers = Int.max

    /// Points are penalties here — rolling a die's highest face scores 0.
    static let lowestScoreWins = true

    static let rules: [String] = [
        "Roll all 15 dice. Every die that lands is worth points you do not want — rolling a die's highest face scores 0, and each face below that costs more.",
        "A 1 is the worst result on any die, costing that die's full size. A 1 on a d12 costs 12, not 11.",
        "Bank at least one die each roll, then roll what is left. Keep going until every die is banked.",
        "Lowest total wins. In a group chat everyone rolls once; if the best score is tied, the game restarts."
    ]
}
