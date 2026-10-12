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
/// Two seats, because every pass-and-play game in the suite builds its
/// match with `TurnMatch.localTwoPlayer()` — checked, not assumed. A match
/// with more seats than there are names falls back to "Player N" for the
/// rest rather than refusing to label them.
enum PlayerNames {

    /// How many names the player can set.
    ///
    /// Not a limit on seats — `TurnMatch.local(playerCount:)` will build
    /// any number — just on how many this bothers to ask for.
    static let seatCount = 2

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

// MARK: - The field

/// One seat's name, in Settings.
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
