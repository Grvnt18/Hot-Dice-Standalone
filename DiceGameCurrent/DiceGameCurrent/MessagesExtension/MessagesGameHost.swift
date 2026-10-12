import SwiftUI
import Messages

// MARK: - The store

/// What the extension knows, in one observable place.
///
/// `ObservableObject` with `@Published`, not `@Observable` — see
/// PLATFORM.txt. The view controller writes to it from Messages'
/// callbacks; the SwiftUI views read it and ask it to send.
final class MessagesStore: ObservableObject {

    /// Compact or expanded. Every layout decision in the extension comes
    /// down to this one value.
    @Published var style: MSMessagesAppPresentationStyle = .compact

    /// The message the player tapped, if they tapped one. Nil means they
    /// opened the app from the drawer, which is a new match.
    @Published private(set) var selected: MSMessage?

    /// Set when an insert fails, and shown rather than swallowed: a turn
    /// that silently did not send is a player waiting forever on a move
    /// they believe they made.
    @Published var sendError: String?

    /// Which game the player picked from the menu, for a NEW match.
    ///
    /// Set only by `startNew`. While it holds a value the player is
    /// composing a fresh chain, whatever message happens to be selected —
    /// which is the whole of "start a second game without finishing the
    /// first". It takes precedence over the selected message's own game
    /// precisely because an explicit pick is a newer intention than the
    /// bubble that was tapped to get here.
    @Published private(set) var chosenGameID: String?

    private(set) var conversation: MSConversation?

    /// Set by the view controller. The store never holds a conversation's
    /// insert path itself.
    var onSend: ((MSMessage) -> Void)?
    var onRequestExpanded: (() -> Void)?

    /// Puts the extension back to the strip above the thread.
    ///
    /// This is what the close control does, and the distinction matters:
    /// it closes the VIEW, not the match. A match lives in its message, so
    /// leaving one is just leaving it — and a player quits by not replying,
    /// the same way they would abandon any conversation. There is nothing
    /// to confirm and nothing to lose, which is why there is no "are you
    /// sure".
    var onClose: (() -> Void)?

    func update(conversation: MSConversation?,
                selected: MSMessage?,
                style: MSMessagesAppPresentationStyle) {
        self.conversation = conversation
        self.selected = selected
        self.style = style
        // A tapped message decides the game; the picker is for new matches
        // only. Cleared here so a stale choice cannot survive into a
        // received turn of a different game.
        // Cleared when the player taps a DIFFERENT message, which is a new
        // intention and overrides an earlier pick. Not cleared on every
        // update: `willBecomeActive` and `didReceive` both come through
        // here, and either wiping the pick would drop a player out of the
        // game they had just chosen and back to the menu.
        if selectedKey != previousSelectedKey {
            self.chosenGameID = nil
            self.previousSelectedKey = selectedKey
        }
        // Decoded once per change, not once per redraw.
        self.receivedHeader = try? MatchMessage.header(from: selected)
    }

    private var previousSelectedKey = ""

    /// The player picked a game from the menu: start a fresh chain.
    func startNew(gameID: String) {
        chosenGameID = gameID
        sendError = nil
    }

    /// Back to the menu, to pick a game for a new chain.
    func showPicker() {
        chosenGameID = nil
        selected = nil
        receivedHeader = nil
        sendError = nil
    }

    /// Whether what is on screen is a new match being composed rather than
    /// the selected one being continued. `MatchMessage.Chain` is built from
    /// this, and getting it wrong would mint a new game into an existing
    /// game's bubble.
    var isComposingNew: Bool { chosenGameID != nil }

    func close() {
        onClose?()
    }

    func clearConversation() {
        conversation = nil
        selected = nil
        chosenGameID = nil
        receivedHeader = nil
    }

    func send(_ message: MSMessage) {
        sendError = nil
        onSend?(message)
    }

    func sendFailed() {
        sendError = "That turn didn't send. Try again."
    }

    func requestExpanded() {
        onRequestExpanded?()
    }

    /// The game a received message carries, or nil when there isn't one.
    ///
    /// Cached rather than decoded on demand. This used to be a computed
    /// property doing a base64 decode and a JSON parse, read from three
    /// separate view bodies — so every redraw of the compact strip or the
    /// expanded screen re-parsed the same message two or three times.
    /// `update` is the only place `selected` changes, so it is the only
    /// place this needs recomputing.
    @Published private(set) var receivedHeader: GameEnvelopeHeader?

    /// What identifies the currently selected turn, for change detection.
    ///
    /// `MSMessage` is a reference type and not `Equatable`, so a view
    /// cannot watch the message itself. Its `url` is what actually carries
    /// the turn, so a different turn is a different string — and nil when
    /// nothing is selected.
    var selectedKey: String { selected?.url?.absoluteString ?? "" }

    /// Whether there is a conversation to read yet.
    ///
    /// SwiftUI's `onAppear` is not promised to run after Messages has
    /// handed over the conversation — `viewDidLoad` builds this tree, and
    /// `willBecomeActive` is what supplies the conversation. A view that
    /// read it once, on appear, could come up on the "needs to run inside a
    /// conversation" message and stay there, because nothing would ask
    /// again. This is what it watches instead.
    var isReady: Bool { conversation != nil }
}

// MARK: - The root

/// What the extension draws.
///
/// Two states, and the split is the presentation style rather than
/// anything about the game: compact is a strip, expanded is the game.
struct MessagesRootView: View {

    @ObservedObject var store: MessagesStore

    var body: some View {
        ZStack {
            WoodTiledBackground(fraction: MenuTimber.fraction)
                .ignoresSafeArea()
            content
        }
        // Pinned like every screen in the suite — see DiceGameShell's note.
        .dynamicTypeSize(.large)
        .preferredColorScheme(.dark)
        // The app registers fonts from GameHubView.onAppear and from
        // DiceSceneAssembler. Neither runs here, and registering in the
        // view controller's init is the early-lifecycle shape that has
        // caused silent launch failures before — so it happens here, in
        // the view lifecycle, exactly as the hub does it.
        .onAppear { AppFonts.registerIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if store.style == .compact {
            MessagesCompactView(store: store)
        } else {
            MessagesExpandedView(store: store)
        }
    }
}

// MARK: - Compact

/// The strip above the keyboard.
///
/// A few hundred points tall, and no game in the suite fits it: every one
/// derives a square playfield from the height it is given. So this says
/// where the match is and nothing else, and a tap asks for the room to
/// play in.
struct MessagesCompactView: View {

    @ObservedObject var store: MessagesStore

    var body: some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            store.requestExpanded()
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.poppins(15, .semibold))
                Text("Tap to play")
                    .font(.poppins(12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var title: String {
        guard let header = store.receivedHeader else { return "Hot Dice" }
        return GameCatalog.all
            .first { $0.id == header.game }?
            .displayName ?? "Hot Dice"
    }
}

// MARK: - Expanded

/// The full screen: either the list of games, or one of them.
struct MessagesExpandedView: View {

    @ObservedObject var store: MessagesStore

    var body: some View {
        VStack(spacing: 0) {
            MessagesChromeBar(store: store, showNewGame: gameID != nil)
            if let error = store.sendError {
                Text(error)
                    .font(.poppins(12))
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.75))
            }
            gameBody(gameID)
        }
    }

    /// The game to show: the one in the tapped message, or the one the
    /// player picked from the list.
    private var gameID: String? {
        // The pick first. A player who tapped a game bubble and then chose
        // "New game" means the new one, and the old message is still
        // selected underneath — see MessagesStore.chosenGameID.
        store.chosenGameID ?? store.receivedHeader?.game
    }

    /// Named `gameBody`, not `body(forGame:)`: a `View` already has a
    /// `body`, and a second thing of that name in the same type is a
    /// confusion waiting for whoever reads it next.
    @ViewBuilder
    private func gameBody(_ id: String?) -> some View {
        if let id {
            MessagesGameRouter(store: store, gameID: id)
        } else if store.selected != nil, !store.isComposingNew {
            // A message was tapped and its payload would not read. Falling
            // through to the game list here showed somebody who tapped a
            // damaged turn a cheerful menu of new games, with no hint that
            // the thing they tapped was the problem.
            MessagesProblemView(
                message: "This message doesn't contain a game this "
                       + "version can read."
            )
        } else {
            MessagesGamePicker(store: store)
        }
    }
}

// MARK: - Chrome

/// Close on the left, New game on the right.
///
/// The two controls a player needs at every moment in a thread, and
/// neither is a game's business — which is why they live here, above
/// whatever `gameBody` draws, rather than being added to ten screens.
///
/// **Close does not end anything.** A match is its message: it stays in
/// the transcript whether anyone is looking at it or not, so closing the
/// view is just closing the view. Quitting a game means not replying to
/// it, the same way you abandon any conversation. Nothing to confirm.
///
/// **New game is always one tap.** Pick from the menu, send it, and it is
/// its own chain in the same thread — no need to finish, or even to touch,
/// whatever is already going on. Hidden only when the menu is already what
/// is on screen, where it would do nothing.
struct MessagesChromeBar: View {

    @ObservedObject var store: MessagesStore
    let showNewGame: Bool

    var body: some View {
        HStack(spacing: 8) {
            chip("Close", icon: "chevron.down") {
                store.close()
            }
            Spacer(minLength: 8)
            if showNewGame {
                chip("New game", icon: "plus") {
                    store.showPicker()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func chip(_ title: String,
                      icon: String,
                      action: @escaping () -> Void) -> some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.poppins(12, .semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            // 44pt is the tap-target floor the suite checks everywhere
            // else — see tools_bandlayout_verify.
            .frame(height: 44)
            .contentShape(Rectangle())
            .pixelPanel(elevation: .lifted)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Picking a game

/// The ten sendable games.
///
/// Built from `GameCatalog`, filtered on `isSendable` — Free Roll is a solo
/// sandbox with no opponent state, so it has nothing to put in a message.
/// Filtered rather than listed again, so a game added to the suite appears
/// here without this file being touched.
struct MessagesGamePicker: View {

    @ObservedObject var store: MessagesStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10),
                                count: 2)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(sendable) { entry in
                    tile(entry)
                }
            }
            .padding(14)
        }
    }

    private var sendable: [GameCatalogEntry] {
        GameCatalog.all.filter { $0.isSendable }
    }

    private func tile(_ entry: GameCatalogEntry) -> some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            store.startNew(gameID: entry.id)
        } label: {
            Text(entry.tileName.uppercased())
                .font(.poppins(14, .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.shared.accentTextColor)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .pixelPanel(fill: .solid(AppTheme.shared.accentColor),
                            elevation: .lifted)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Routing

/// One game, by id.
///
/// Explicit rather than clever. Swift 5.7 cannot hold a protocol with an
/// associated type in a collection without ceremony that buys nothing
/// (`GameWireCheck.runAll` says the same), and more to the point each game
/// decodes a different `State` — so a switch is what this is.
///
/// **Only Rolls is wired.** The other nine have Codable state and a
/// measured payload already; what they do not have is an injectable
/// starting position — every screen builds its own `TurnMatch` in a
/// `@State` initialiser. Giving them one is mechanical, and it comes after
/// a turn has actually crossed between two simulated conversations, so
/// that the seam is cut to fit something that works rather than to a
/// guess.
struct MessagesGameRouter: View {

    @ObservedObject var store: MessagesStore
    let gameID: String

    var body: some View {
        switch gameID {
        case RollsGameState.gameID:
            MessagesRollsHost(store: store)
        default:
            MessagesNotReadyView(gameID: gameID)
        }
    }
}

/// A game this build cannot play in a conversation yet.
///
/// Named rather than blank: a player who taps a bubble and gets nothing
/// learns nothing, and the id is the one fact worth showing.
struct MessagesNotReadyView: View {

    let gameID: String

    var body: some View {
        VStack(spacing: 10) {
            Text(name)
                .font(.poppins(18, .semibold))
            Text("This one isn't playable in Messages yet. "
                 + "Open Hot Dice to play it pass-and-play.")
                .font(.poppins(13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var name: String {
        GameCatalog.all.first { $0.id == gameID }?.displayName ?? gameID
    }
}
