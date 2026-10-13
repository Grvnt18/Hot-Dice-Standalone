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

    /// The guide, as titled sections.
    ///
    /// One guide, not two. There used to be a second, shorter array for the
    /// sheet a player opens mid-match, on the reasoning that they want "what
    /// does my button do" rather than the differential table. What it
    /// actually produced was a guide that left things out being the one you
    /// could reach fastest, with the real rules two taps away on a screen
    /// you have to quit the match to see. Both screens show this now.
    static var rules: [GameRuleSection] { get }

    /// Upper bound on participants. Two for everything except Rolls, which
    /// has no ceiling beyond what a group chat contains.
    static var maxPlayers: Int { get }

    /// How many seats this game's PASS-AND-PLAY screen actually runs.
    ///
    /// Not the same claim as `maxPlayers`, and conflating the two would
    /// have shipped a bug. `maxPlayers` is what the RULES allow, which is
    /// why Rolls is `Int.max` — a single round has no turn order, so a
    /// whole group chat can play it. But Rolls' standalone screen has no
    /// `TurnMatch` at all: it is one tray, one score and
    /// `TurnCompleteOverlay`, and multi-seat Rolls is a thing the Messages
    /// version does by reading a conversation's participants. Asking who
    /// is playing before it would be asking a question with no consumer.
    ///
    /// So this is what `MatchSetupView` offers, and it is a claim about
    /// the screen rather than about the game. One means "does not seat
    /// anybody" and skips the gate entirely — Free Roll and Rolls.
    static var localSeats: Int { get }

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

    /// The name on the hub tile, when the full one will not fit.
    ///
    /// Same reason `floorTitle` exists: a name set to span the artwork has
    /// to actually fit beside it, and "Freighter.Yacht.Dinghy" has no
    /// spaces to break on — SwiftUI cannot wrap it, so it sets as one
    /// line half again as wide as the icon above it, at the smallest size
    /// the tile allows.
    static var tileName: String { get }

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

    /// Two, which is right for six of the eleven and for every game whose
    /// screen hosts a `TurnMatch` with a fixed pair. The three that seat
    /// more say so; the two that seat nobody say one.
    static var localSeats: Int { 2 }

    static var floorTitle: String { displayName }

    /// The full name, for the ten games it fits.
    static var tileName: String { displayName }

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

    /// A diagram under the text, where prose is the wrong medium.
    ///
    /// Three rules in the suite are shapes rather than sentences: what a
    /// rosette looks like and what standing on one does, the route a piece
    /// walks around the Royal UR board, and how a Boneheads column
    /// multiplies. Each was a paragraph that readers had to rebuild into a
    /// picture in their head, and the Boneheads one is arithmetic nobody
    /// should have to run by hand to understand the rule.
    ///
    /// Empty for the other fifty-odd sections, which say what they mean.
    ///
    /// A list rather than one: Royal UR's movement rule needs the route AND
    /// what a rosette does, and they illustrate the same paragraph.
    var figures: [GuideFigure] = []

    init(title: String, body: String, figures: [GuideFigure] = []) {
        self.title = title
        self.body = body
        self.figures = figures
    }

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

    /// What the hub tile says — `displayName` for all but one. See
    /// `SuiteGame.tileName`.
    let tileName: String

    let tagline: String

    /// The game's own How to Play text.
    ///
    /// Carried here so the hub can offer every guide without opening a
    /// game — the bubble cluster in `GuideBubbleCluster` is built from
    /// these, and a game whose rules are empty would open a blank sheet.
    let rules: [GameRuleSection]

    /// Builds the game's root view, given the action that returns to the
    /// hub.
    ///
    /// The dismissal is passed *in* rather than the game reaching for an
    /// environment dismiss: games are presented full screen precisely so
    /// they keep the whole display, which means there is no navigation
    /// chrome to go back with — each game draws its own control.
    let makeView: (@escaping () -> Void) -> AnyView

    /// Whether a turn can be sent to someone else — `SuiteGame.isSendable`.
    ///
    /// Carried here because the Messages extension lists games from this
    /// catalogue and must not offer Free Roll: a solo sandbox has no
    /// opponent state, so there is nothing to put in a message. The hub
    /// shows all eleven; the extension shows the ten that can travel.
    let isSendable: Bool

    /// Upper bound on participants — `SuiteGame.maxPlayers`.
    ///
    /// The extension needs this before it builds a match: a conversation
    /// can hold more people than a two-player game can seat, and the
    /// roster has to be refused at that point rather than silently
    /// truncated into a game two of the five participants are playing.
    let maxPlayers: Int

    /// How many seats pass-and-play offers — `SuiteGame.localSeats`.
    ///
    /// Carried here because the hub's setup gate is the only thing that
    /// reads it, and the hub has an entry rather than a type.
    let localSeats: Int

    init(
        id: String,
        displayName: String,
        tileName: String,
        tagline: String,
        rules: [GameRuleSection] = [],
        isSendable: Bool = true,
        maxPlayers: Int = 2,
        localSeats: Int = 2,
        makeView: @escaping (@escaping () -> Void) -> AnyView
    ) {
        self.id = id
        self.displayName = displayName
        self.tileName = tileName
        self.tagline = tagline
        self.rules = rules
        self.isSendable = isSendable
        self.maxPlayers = maxPlayers
        self.localSeats = localSeats
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
            tileName: G.tileName,
            tagline: G.tagline,
            rules: G.rules,
            isSendable: G.isSendable,
            maxPlayers: G.maxPlayers,
            localSeats: G.localSeats,
            makeView: makeView
        )
    }
}

enum GameCatalog {

    /// Hub order. Rolls and Free Roll open; the rest render as "Soon"
    /// tiles until each is built, in the order listed here.
    static let all: [GameCatalogEntry] = [
        // The host, not the screen. `DiceGameScreen` is still the whole of
        // Rolls and is untouched — see RollsPassAndPlayHost, which drives
        // one of them per seat.
        GameCatalogEntry(RollsGame.self) { onExit in
            AnyView(RollsPassAndPlayHost(onExit: onExit))
        },
        GameCatalogEntry(GeneralsGame.self) { onExit in
            AnyView(GeneralsScreen(onExit: onExit))
        },
        GameCatalogEntry(ThreeThousandGame.self) { onExit in
            AnyView(ThreeThousandScreen(onExit: onExit))
        },
        GameCatalogEntry(HogGame.self) { onExit in
            AnyView(HogScreen(onExit: onExit))
        },
        GameCatalogEntry(RoyalUrGame.self) { onExit in
            AnyView(RoyalUrScreen(onExit: onExit))
        },
        GameCatalogEntry(BoneheadsGame.self) { onExit in
            AnyView(BoneheadsScreen(onExit: onExit))
        },
        GameCatalogEntry(FreighterYachtDinghyGame.self) { onExit in
            AnyView(FreighterYachtDinghyScreen(onExit: onExit))
        },
        GameCatalogEntry(RollbotsGame.self) { onExit in
            AnyView(RollbotsScreen(onExit: onExit))
        },
        GameCatalogEntry(BaseballDiceGame.self) { onExit in
            AnyView(BaseballDiceScreen(onExit: onExit))
        },
        GameCatalogEntry(JackpotGame.self) { onExit in
            AnyView(JackpotScreen(onExit: onExit))
        },
        // Last, and that is the point: Free Roll is the only solo entry —
        // a sandbox with no opponent and no win condition — so it sits
        // below the ten games rather than between two of them.
        GameCatalogEntry(FreeRollGame.self) { onExit in
            AnyView(FreeRollScreen(onExit: onExit))
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
    static let tagline = "Beat the pitch. Take the plate."

    /// The floor is the ballpark itself, so it carries no wordmark.
    static let floorTitle = ""

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "  * Players: 2. Player 1 pitches first; Player 2 bats first (Home Team advantage).\n  * Length: Selected before match start (3, 6, or 9 innings). Three outs per half-inning.\n  * Objective: Score the most runs by matching pitch and swing tactics."
        ),
        GameRuleSection(
            title: "Turn Structure",
            body: "  1. Pitcher Style Selection: The pitcher selects a Pitching Style for\n     the entire half-inning, confirming their choice to end the step.\n  2. At-Bat: For each at-bat, the batter chooses a Swing. The pitch is drawn automatically based on the pitcher’s\n     style, and both dice are rolled simultaneously.\n  3. Inning Handover: Upon the third out, the half-inning ends. Roles swap,\n     and the new pitcher selects their Pitching Style."
        ),
        GameRuleSection(
            title: "Pitching Styles & Swing Matchups",
            body: "  Pitching Styles:\n    * Power Pitcher: Heavy emphasis on Fastballs; secondary Changeup and Slider.\n    * Crafty: Heavy emphasis on Changeups; secondary Fastball and Slider.\n    * Breaking Ball: Heavy emphasis on Sliders; secondary Fastball and Changeup.\n\n  Strategic Cycle:\n    * Fastball beats Power Swing | Loses to Patient Swing\n    * Changeup beats Patient Swing | Loses to Contact Swing\n    * Slider beats Contact Swing | Loses to Power Swing"
        ),
        GameRuleSection(
            title: "Dice & Matchup Mechanics",
            body: "  Matchup Type                        Batter Dice               Pitcher Dice\n  -----------------------------------------------------------------------------\n  Favoured (Swing Beats Pitch)        2x Swing Die (Keep High)  1d4\n  Even (Neutral Matchup)              1x Swing Die              1d8\n  Unfavoured: Fastball vs. Power      1d12                      2d12 (Keep High)\n  Unfavoured: Changeup vs. Patient    1d8                       1d10\n  Unfavoured: Slider vs. Contact      1d10                      1d12\n\n  * Base Swing Dice Sizes: Patient (1d8), Contact (1d10), Power (1d12)."
        ),
        GameRuleSection(
            title: "Scoring Matrix (Batter Roll Minus Pitcher Roll)",
            body: "  Differential    Result        Effect\n  -----------------------------------------------------------------------------\n  -5 or lower     Strikeout     1 Out\n  -4 to +1        Field Out     1 Out (Triggers Double Play if Pitcher roll is\n                                even with a runner on 1st)\n  +2              Walk          Batter to 1st; forced runners advance 1 base\n  +3 to +4        Single        Batter to 1st; all base runners advance 1 base\n  +5              Double        Batter to 2nd; all base runners advance 2 bases\n  +6              Triple        Batter to 3rd; all base runners score\n  +7 to +9        Deep Out      1 Out; all base runners advance 1 base, so a\n                                runner on 3rd scores (Unless 3rd out)\n  +10 or higher   Home Run      Batter and all base runners score"
        ),
        GameRuleSection(
            title: "Special Rules",
            body: "  * Favoured Immunity: A favoured swing cannot strike out (minimum net value is -3).\n  * Double Maximum: Rolling the maximum value on both dice during a favoured swing\n    results in an automatic Home Run regardless of differential.\n  * Third-Out Catch: A Deep Out recorded as the third out immediately ends\n    the half-inning; no run scores."
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

    /// Pass-and-play seats, as many as the scoreboard fits.
    ///
    /// This was 1, on the true-at-the-time reading that `DiceGameScreen`
    /// has no `TurnMatch` — one tray, one score, `TurnCompleteOverlay`,
    /// nobody to name. That made Rolls the one game in the suite whose own
    /// guide describes an opponent it did not have, and skipping the setup
    /// gate hid the gap rather than closing it.
    ///
    /// `RollsPassAndPlayHost` closes it: one `DiceGameScreen` per seat,
    /// one shared deal, the handover gate between rounds. The screen
    /// itself is still untouched.
    static let localSeats = Int.max

    /// Points are penalties here — rolling a die's highest face scores 0.
    static let lowestScoreWins = true

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "  * Players: 2+\n  * Dice Pool: 15 total (12x d6, 1x d8, 1x d10, 1x d12).\n  * Objective: Bank all 15 dice; lowest cumulative score wins."
        ),
        GameRuleSection(
            title: "Player Turn",
            body: "  1. Roll all remaining active dice in the pool.\n  2. Select and bank at least one die.\n  3. Re-roll all unbanked dice. Repeat until all 15 dice are banked to\n     finish the turn."
        ),
        GameRuleSection(
            title: "Scoring Structure",
            body: "  A banked die scores based on its differential from its highest face value.\n  Lower scores are better.\n\n  Die Type    Highest Face (0 Pts)    Penalty for Rolling a 1\n  -----------------------------------------------------------------------------\n  d6          6                       6 Points\n  d8          8                       8 Points\n  d10         10                      10 Points\n  d12         12                      12 Points\n\n  * Formula: Score = Max Value - Rolled Face\n  * Bust: Rolling a 1 scores penalty points equal to the die's total sides."
        )
    ]
}
