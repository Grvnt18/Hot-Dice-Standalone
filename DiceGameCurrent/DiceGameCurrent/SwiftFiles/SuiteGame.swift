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

    /// Rules for the How to Play sheet, as titled sections.
    static var rules: [GameRuleSection] { get }

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

    /// What the playfield floor says beneath the dice.
    ///
    /// Defaults to `displayName`. A game only overrides it when its name
    /// is too long to read at the size the script is actually drawn —
    /// the floor wordmark spans 45% of the playfield width, which suits
    /// "Jackpot" and defeats "Freighter.Yacht.Dinghy".
    static var floorTitle: String { get }

    /// The shape this game's floor facets carry. See `FloorMotif`.
    static var floorMotif: FloorMotif { get }

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
    static var floorTitle: String { displayName }

    /// No mark unless a game asks for one, so a game added later is not
    /// obliged to have art before it can ship.
    static var floorMotif: FloorMotif { .none }
    static var lowestScoreWins: Bool { false }
    static var isSendable: Bool { true }
}

/// One titled block of a game's rules.
///
/// Titled sections rather than bare paragraphs because that is the shape
/// HowToPlayView already rendered for Rolls, and it reads far better than
/// a wall of text — the headings let you find the bit you actually wanted.
struct GameRuleSection: Identifiable {
    let title: String
    let body: String

    /// Titles are unique within a game, which is all ForEach needs.
    var id: String { title }
}

// MARK: - The catalogue

/// Every game in the suite, in hub order.
///
/// Type-erased into a description rather than an array of metatypes, so the
/// hub renders a tile from a value instead of reaching into a generic type
/// per cell.
///
/// It once carried an availability flag and the hub drew a greyed "soon"
/// tile for the games that had no view yet. All ten have one now, so the
/// flag was permanently true and the whole branch unreachable; it came out
/// rather than sitting there untestable.
struct GameCatalogEntry: Identifiable {
    let id: String
    let displayName: String
    let tagline: String

    /// Builds the game's root view, given the action that returns to the
    /// hub.
    ///
    /// The dismissal is passed *in* rather than the game reaching for an
    /// environment dismiss: games are presented full screen precisely so
    /// they keep the whole display, which means there is no navigation
    /// chrome to go back with — each game draws its own control.
    let makeView: (@escaping () -> Void) -> AnyView

    init(
        id: String,
        displayName: String,
        tagline: String,
        makeView: @escaping (@escaping () -> Void) -> AnyView
    ) {
        self.id = id
        self.displayName = displayName
        self.tagline = tagline
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
        GameCatalogEntry(JackpotGame.self) { onExit in
            AnyView(JackpotScreen(onExit: onExit))
        },
        GameCatalogEntry(HogGame.self) { onExit in
            AnyView(HogScreen(onExit: onExit))
        },
        GameCatalogEntry(GeneralsGame.self) { onExit in
            AnyView(GeneralsScreen(onExit: onExit))
        },
        GameCatalogEntry(ThreeThousandGame.self) { onExit in
            AnyView(ThreeThousandScreen(onExit: onExit))
        },
        GameCatalogEntry(FreighterYachtDinghyGame.self) { onExit in
            AnyView(FreighterYachtDinghyScreen(onExit: onExit))
        },
        GameCatalogEntry(RoyalUrGame.self) { onExit in
            AnyView(RoyalUrScreen(onExit: onExit))
        },
        GameCatalogEntry(RollbotsGame.self) { onExit in
            AnyView(RollbotsScreen(onExit: onExit))
        },
        GameCatalogEntry(BaseballDiceGame.self) { onExit in
            AnyView(BaseballDiceScreen(onExit: onExit))
        },
        GameCatalogEntry(BoneheadsGame.self) { onExit in
            AnyView(BoneheadsScreen(onExit: onExit))
        }
    ]
}

// MARK: - Rolls

/// Rolls' entry in the suite. The game itself is unchanged — this only
/// declares what the hub and rules sheet need to know about it.
/// Baseball Dice.
///
/// The id is `baseball_dice` and the artwork is `icon-baseball_dice.png` —
/// GameIcons derives the filename from the id, so the two cannot drift.
enum BaseballDiceGame: SuiteGame {
    static let id = "baseball_dice"
    static let displayName = "Baseball Dice"
    static let tagline = "Guess the pitch. Take the extra base."

    /// The floor is the ballpark itself, so it carries no wordmark.
    static let floorTitle = ""

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "The Game",
            body: "Pick a match length first — 3 innings is short, 6 medium, 9 extra long. Three outs to a half-inning, and the side batting last has the advantage it does in real baseball."
        ),
        GameRuleSection(
            title: "Pitching",
            body: "At the start of each half-inning the pitcher picks a style and keeps it hidden: Power Pitcher leans on the fastball, Crafty on the changeup, Breaking Ball on the slider. The app throws the actual pitch from that mix every at-bat, so even the pitcher does not know exactly what is coming."
        ),
        GameRuleSection(
            title: "Swinging",
            body: "The batter picks a swing without seeing the pitch. Patient beats the Fastball, Contact beats the Changeup, Power beats the Slider — and each loses to the pitch it cannot handle. Guess right and you roll two dice and keep the best against the pitcher's d4."
        ),
        GameRuleSection(
            title: "The Result",
            body: "Subtract the pitcher's roll from the batter's. -5 or worse is a strikeout, -4 to +1 a field out, +2 a walk, +3 to +4 a single, +5 a double, +6 a triple, +7 to +9 caught at the wall, and +10 or better a home run."
        ),
        GameRuleSection(
            title: "Worth Knowing",
            body: "A favoured swing can never strike out — the worst gap it can produce is -3. Rolling your die's maximum on both dice of a favoured swing is an automatic home run whatever the table says. A deep out still scores a runner from third, and a field out with a runner on first is a double play when the pitcher's roll is even."
        ),
        GameRuleSection(
            title: "Winning",
            body: "Most runs when the innings run out. A tie plays extra innings, in pairs, until someone leads at the end of one."
        )
    ]
}

enum RollsGame: SuiteGame {
    static let id = RollsGameState.gameID
    static let displayName = "Rolls"
    static let tagline = "One round. Lowest score takes it."

    /// The only game with no player ceiling: a single round has no turn
    /// order, so a whole group chat can play at once.
    static let maxPlayers = Int.max

    /// Points are penalties here — rolling a die's highest face scores 0.
    static let lowestScoreWins = true

    /// Moved here verbatim from HowToPlayView, which hardcoded them. The
    /// wording was fine; it was living in the settings sheet, which meant
    /// every game showed Rolls' rules.
    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "The Pool",
            body: "You start with 15 dice: twelve 6-sided, one 8-sided, one 10-sided, and one 12-sided."
        ),
        GameRuleSection(
            title: "Rolling",
            body: "Tap Begin to roll every die still in the pool. Tap any settled die to select it, then tap Roll again to bank your selection and re-roll everything left."
        ),
        GameRuleSection(
            title: "Scoring",
            body: "Lower is better. Banking a die scores it against its own best face: its highest number scores 0, and every face below that costs one point per step down — except a 1, which always costs the die's full number of sides, its worst possible result."
        ),
        GameRuleSection(
            title: "Banking",
            body: "You must bank at least one die from a roll before rerolling the rest. Selecting every remaining die turns the Roll button into Finish — confirming then banks everything and ends the turn."
        ),
        GameRuleSection(
            title: "Winning",
            body: "The game ends once every die has been banked. Add up the points from every die you banked — the lowest total wins."
        )
    ]
}
