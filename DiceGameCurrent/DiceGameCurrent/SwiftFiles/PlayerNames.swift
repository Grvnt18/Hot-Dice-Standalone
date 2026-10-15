import SwiftUI

/// What the two players are called.
///
/// **This is a standalone-only thing, and that is the whole reason the two
/// versions of Hot Dice are separate products.** An iMessage extension is
/// handed opaque per-conversation UUIDs and no names or avatars, so the
/// best it can ever say is "Player 1" — which is why
/// `TurnMatch.displayName(for:)` was positional. A game played by two
/// people round one table has no such excuse: it can simply ask.
///
/// Every screen gets this for free. All thirty-three places that label a
/// seat already go through `displayName(for:)`, `activeDisplayName` or
/// `seatNames`, so teaching the one function to consult this store names
/// the scoreboards, the handover gates, the result screens and Rollbots'
/// own chrome in a single change.
///
/// Names are stored per SEAT and shared across the suite, not per game: a
/// pair who have typed themselves in once should not have to do it again
/// for the next game, and the seat a name belongs to is the only thing any
/// screen asks about. How MANY seats there are is a separate question, and
/// `MatchSetup` below owns it.
enum PlayerNames {

    /// The longest name that still fits a scoreboard tile.
    ///
    /// The handover gate sets the active name at 46pt with `lineLimit(2)`
    /// and the scoreboard at 11pt in a seat tile that is half the screen
    /// less its padding. Twelve characters is comfortably inside both; it
    /// is a cap on typing rather than a promise about layout, which
    /// `minimumScaleFactor` already handles.
    static let maxLength = 12

    private static func key(_ seat: Int) -> String { "players.name.\(seat)" }

    /// The stored name for a seat, or nil when it has none.
    ///
    /// Trimmed, and empty counts as nil: a player who clears the field
    /// wants "Player 1" back, not a blank scoreboard.
    static func name(seat: Int) -> String? {
        let stored = SharedDefaults.store.string(forKey: key(seat)) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setName(_ name: String, seat: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        SharedDefaults.store.set(String(trimmed.prefix(maxLength)),
                                 forKey: key(seat))
    }

    /// What to call a seat on screen: their name, or the positional label.
    ///
    /// The one place the fallback is spelled, so a screen cannot invent a
    /// different one. `TurnMatch.displayName(for:)` is its only caller that
    /// matters; everything else reaches it through that.
    static func label(seat: Int) -> String {
        name(seat: seat) ?? "Player \(seat + 1)"
    }
}

// MARK: - How many are playing

/// How many seats the match about to start has.
///
/// Kept apart from `PlayerNames` because the two answer different
/// questions and are scoped differently: a name belongs to a seat and
/// holds across the suite, while a seat COUNT belongs to a game. Four
/// people play Rolls at this table and two play Royal UR, and neither
/// choice should disturb the other — the same reasoning `GameScope` makes
/// for the table colour, and it reads `GameScope.activeGameID` to do it.
enum MatchSetup {

    /// The most seats pass-and-play offers, whatever a game's own ceiling
    /// says.
    ///
    /// Three of the games are `maxPlayers = Int.max`, which is true of the
    /// RULES and useless as an offer: the limit here is the scoreboard,
    /// which lays its seat tiles out in one row across the screen.
    ///
    /// Measured, at Poppins-SemiBold 11pt on the narrowest phone this app
    /// meets (375pt): four tiles come to 80.2pt each against about 75pt
    /// for a twelve-character name, so four fits. Five is 62.2pt and needs
    /// every name scaled; six is 50.2pt and truncates past the 0.7 floor.
    /// See the note on `MatchScoreboard.seat`, which is where those
    /// numbers are used.
    static let maxSeats = 4

    private static func key(_ gameID: String) -> String {
        "players.count.\(gameID)"
    }

    /// How many seats a game is set to, clamped to what it can offer.
    ///
    /// `limit` is the game's own `localSeats`, so a two-player game cannot
    /// return three however the store was left by an earlier version.
    static func seatCount(for gameID: String, limit: Int) -> Int {
        let ceiling = max(2, min(limit, maxSeats))
        let stored = SharedDefaults.store.integer(forKey: key(gameID))
        return min(max(2, stored), ceiling)
    }

    static func setSeatCount(_ count: Int, for gameID: String) {
        SharedDefaults.store.set(count, forKey: key(gameID))
    }

    /// The seat count for the match being built right now.
    ///
    /// This is what `TurnMatch.passAndPlay()` reads, and the reason it can
    /// is that `MatchSetupView` has already written it: the gate runs
    /// BEFORE the game's view is constructed, so the `@State` match in
    /// each screen is initialised from a value that is already there. A
    /// store that was somehow never written reads 0 and clamps to two,
    /// which is the count every screen had before any of this.
    ///
    /// `GameScope.activeGameID` rather than a parameter, because the
    /// eleven screens build their own match in a property initialiser and
    /// have nothing to pass — the same reason `AppTheme` reads the scope
    /// instead of being handed it.
    static var currentSeatCount: Int {
        guard let gameID = GameScope.activeGameID else { return 2 }
        return seatCount(for: gameID, limit: maxSeats)
    }
}

// MARK: - The field

/// One seat's name.
///
/// Lived in Settings until the popup existed, which was the wrong place
/// for it twice over: a player had to know the setting was there before
/// their first game, and it asked for exactly two names on a suite where
/// four of the games seat more than two. It is now part of
/// `MatchSetupView` and is asked at the moment it is needed.
///
/// Writes straight through on every keystroke rather than on submit: there
/// is no Done button on this sheet and a name typed and then dismissed by
/// swiping would otherwise be lost. `SharedDefaults` is a plist write of a
/// string a dozen characters long, so the cost of doing it per character is
/// not worth a more careful dance.
struct PlayerNameField: View {

    let seat: Int

    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Text("Player \(seat + 1)")
                .font(.poppins(13))
                .foregroundStyle(MenuInk.dim)
                .frame(width: 66, alignment: .leading)

            TextField("Player \(seat + 1)", text: $text)
                .font(.poppins(15))
                .foregroundStyle(MenuInk.text)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .onValueChange(of: text) { typed in
                    // Capped here as well as in the store, so the field
                    // cannot show more than it will keep.
                    if typed.count > PlayerNames.maxLength {
                        text = String(typed.prefix(PlayerNames.maxLength))
                        return
                    }
                    PlayerNames.setName(typed, seat: seat)
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .frame(maxWidth: .infinity)
                .pixelWell(radius: ControlShape.cornerRadius)
        }
        // Read on appear rather than in an initialiser: @State's initial
        // value is captured once and would go stale if the sheet were
        // rebuilt after a name changed somewhere else.
        .onAppear { text = PlayerNames.name(seat: seat) ?? "" }
    }
}

// MARK: - The popup

/// What stands between tapping a tile and the game appearing: who is
/// playing, and how many of them.
///
/// **It has to be a gate rather than a sheet over the game**, and that is
/// the whole shape of this file. Every one of the eleven screens builds
/// its match in a property initialiser —
/// `@State private var match = TurnMatch.passAndPlay()` — which runs when
/// the view is CONSTRUCTED. A sheet presented from inside the game would
/// therefore be asking after the answer had already been used. So the
/// game's view is not built at all until Start is pressed, and the count
/// is in `MatchSetup` by the time it is.
///
/// Skipped entirely for the two screens that seat nobody — Free Roll and
/// Rolls, both `localSeats = 1`. Neither hosts a `TurnMatch` and neither
/// labels anyone, so asking them who is playing would be asking a
/// question with no consumer. `localSeats` rather than `maxPlayers`
/// deliberately: Rolls' rules have no ceiling at all, and its standalone
/// screen still seats one.
struct MatchSetupGate: View {
    let entry: GameCatalogEntry
    let onExit: () -> Void

    @State private var ready = false

    var body: some View {
        if ready || entry.localSeats < 2 {
            entry.makeView(onExit)
        } else {
            MatchSetupView(entry: entry,
                           onStart: { ready = true },
                           onCancel: onExit)
        }
    }
}

/// The gate's own screen.
struct MatchSetupView: View {

    let entry: GameCatalogEntry
    let onStart: () -> Void
    let onCancel: () -> Void

    @ObservedObject private var theme = AppTheme.shared

    /// Read on appear rather than in an initialiser, for the reason
    /// `PlayerNameField` gives: a `@State` default is captured once, and
    /// this one depends on which game is being opened.
    @State private var seats = 2

    /// The counts this game can offer. One value means no choice to make,
    /// and the picker is left out rather than shown with a single option.
    private var options: [Int] {
        Array(2...max(2, min(entry.localSeats, MatchSetup.maxSeats)))
    }

    var body: some View {
        ZStack {
            WoodTiledBackground()
                .ignoresSafeArea()

            // The same wash as the handover gate, and for a related
            // reason: this sits in front of a game that has not started,
            // and the timber alone would read as the game's own header
            // rather than as something laid over it.
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    if options.count > 1 { seatPicker }
                    nameFields
                    footnote
                    buttons
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 28)
            }
        }
        .dynamicTypeSize(.large)
        .onAppear {
            seats = MatchSetup.seatCount(for: entry.id,
                                         limit: entry.localSeats)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(entry.displayName)
                .font(.poppins(30, .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Who's playing?")
                .font(.poppins(13, .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var seatPicker: some View {
        VStack(spacing: 8) {
            Text("Players")
                .font(.poppins(12, .semibold))
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 8) {
                ForEach(options, id: \.self) { count in
                    seatOption(count)
                }
            }
        }
    }

    private func seatOption(_ count: Int) -> some View {
        let chosen = count == seats
        return Button {
            SoundEngine.shared.play(.buttonTap)
            seats = count
        } label: {
            Text("\(count)")
                .font(.poppins(17, .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                // Load-bearing under `.plain`: that style hit-tests what
                // is DRAWN, and a frame around a Text is layout rather
                // than something to tap. See the note in TurnActionBar.
                .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(chosen ? theme.accentTextColor : .white.opacity(0.75))
        .pixelPanel(fill: .solid(chosen
                                 ? theme.accentColor
                                 : Color.black.opacity(0.35)),
                    elevation: chosen ? .lifted : .resting)
    }

    private var nameFields: some View {
        // `Array(0..<seats)` rather than the range itself: a ForEach over
        // a range wants that range constant, and this one changes as the
        // picker is used.
        VStack(spacing: 10) {
            ForEach(Array(0..<seats), id: \.self) { seat in
                PlayerNameField(seat: seat)
            }
        }
    }

    private var footnote: some View {
        Text("Names show on the scoreboard, the handover screens and "
             + "the result. Leave blank for \"Player 1\".")
            .font(.poppins(11, .semibold))
            .foregroundStyle(.white.opacity(0.6))
            .multilineTextAlignment(.center)
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            Button {
                SoundEngine.shared.play(.menuSelect)
                // Written before the game's view exists — see the note on
                // MatchSetup.currentSeatCount. Always written, including
                // for the games with no picker, so the store is never
                // standing on a default.
                MatchSetup.setSeatCount(seats, for: entry.id)
                onStart()
            } label: {
                Text("Start")
                    .font(.poppins(16))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accentTextColor)
            .pixelPanel(fill: .solid(theme.accentColor), elevation: .lifted)

            Button {
                SoundEngine.shared.play(.buttonTap)
                onCancel()
            } label: {
                Text("Back to Games")
                    .font(.poppins(14))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .pixelPanel(fill: .solid(theme.accentColor.opacity(0.35)),
                        elevation: .resting)
        }
        .padding(.top, 4)
    }
}
