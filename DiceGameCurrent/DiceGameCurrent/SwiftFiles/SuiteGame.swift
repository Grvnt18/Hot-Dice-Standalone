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

    init(
        id: String,
        displayName: String,
        tileName: String,
        tagline: String,
        rules: [GameRuleSection] = [],
        makeView: @escaping (@escaping () -> Void) -> AnyView
    ) {
        self.id = id
        self.displayName = displayName
        self.tileName = tileName
        self.tagline = tagline
        self.rules = rules
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
        GameCatalogEntry(FreeRollGame.self) { onExit in
            AnyView(FreeRollScreen(onExit: onExit))
        },
        GameCatalogEntry(JackpotGame.self) { onExit in
            AnyView(JackpotScreen(onExit: onExit))
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
            title: "Game Overview",
            body: "Two players. Player 1 pitches first; Player 2 bats first, for the home team advantage. Length is selected before the match starts — 3, 6 or 9 innings — with three outs per half-inning. Score the most runs by matching pitch and swing tactics."
        ),
        GameRuleSection(
            title: "Turn Structure",
            body: "The pitcher secretly selects a Pitching Style for the entire half-inning, confirming their choice to end the step. For each at-bat the batter chooses a Swing without seeing the pitch; the pitch is drawn automatically based on the pitcher's style, and both dice are rolled simultaneously. Upon the third out the half-inning ends, roles swap, and the new pitcher selects their Pitching Style."
        ),
        GameRuleSection(
            title: "Pitching Styles",
            body: "Power Pitcher: heavy emphasis on Fastballs, secondary Changeup and Slider. Crafty: heavy emphasis on Changeups, secondary Fastball and Slider. Breaking Ball: heavy emphasis on Sliders, secondary Fastball and Changeup."
        ),
        GameRuleSection(
            title: "Strategic Cycle",
            body: "Fastball beats Power Swing and loses to Patient Swing. Changeup beats Patient Swing and loses to Contact Swing. Slider beats Contact Swing and loses to Power Swing."
        ),
        GameRuleSection(
            title: "Dice and Matchup Mechanics",
            body: "Favoured, where the swing beats the pitch: 2x swing die keeping the high one, against 1d4. Even, a neutral matchup: 1x swing die against 1d8. Unfavoured Fastball against Power: 1d12 against 2d12 keeping the high one. Unfavoured Changeup against Patient: 1d8 against 1d10. Unfavoured Slider against Contact: 1d10 against 1d12. Base swing dice sizes are Patient 1d8, Contact 1d10, Power 1d12."
        ),
        GameRuleSection(
            title: "Scoring Matrix",
            body: "Take the batter roll minus the pitcher roll. -5 or lower is a Strikeout for 1 out. -4 to +1 is a Field Out for 1 out, triggering a double play if the pitcher roll is even with a runner on 1st. +2 is a Walk, batter to 1st with forced runners advancing 1 base. +3 to +4 is a Single, batter to 1st and all base runners advance 1 base. +5 is a Double, batter to 2nd and all base runners advance 2 bases. +6 is a Triple, batter to 3rd and all base runners score. +7 to +9 is a Deep Out for 1 out, and the runner on 3rd scores unless it is the third out. +10 or higher is a Home Run, batter and all base runners score."
        ),
        GameRuleSection(
            title: "Special Rules",
            body: "Favoured Immunity: a favoured swing cannot strike out, as its minimum net value is -3. Double Maximum: rolling the maximum value on both dice during a favoured swing results in an automatic Home Run regardless of differential. Third-Out Catch: a Deep Out recorded as the third out immediately ends the half-inning, and no run scores."
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

    static let rules: [GameRuleSection] = [
        GameRuleSection(
            title: "Game Overview",
            body: "Two or more players, group play compatible. The dice pool is 15 total: twelve d6, one d8, one d10 and one d12. Bank all 15 dice; lowest cumulative score wins."
        ),
        GameRuleSection(
            title: "Player Turn",
            body: "Roll all remaining active dice in the pool. Select and bank at least one die. Re-roll all unbanked dice, and repeat until all 15 dice are banked to finish the turn."
        ),
        GameRuleSection(
            title: "Scoring Structure",
            body: "A banked die scores based on its differential from its highest face value, and lower scores are better. The formula is Score = Max Value - Rolled Face, so a d6 rolling 6 scores 0, a d8 rolling 8 scores 0, and so on. The exception is rolling a 1, which scores penalty points equal to the die's total sides: 6 points on a d6, 8 on a d8, 10 on a d10 and 12 on a d12."
        )
    ]
}
