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

    /// Which game the player picked for a new match. Nil while the picker
    /// is up.
    @Published var chosenGameID: String?

    private(set) var conversation: MSConversation?

    /// Set by the view controller. The store never holds a conversation's
    /// insert path itself.
    var onSend: ((MSMessage) -> Void)?
    var onRequestExpanded: (() -> Void)?

    func update(conversation: MSConversation?,
                selected: MSMessage?,
                style: MSMessagesAppPresentationStyle) {
        self.conversation = conversation
        self.selected = selected
        self.style = style
        // A tapped message decides the game; the picker is for new matches
        // only. Cleared here so a stale choice cannot survive into a
        // received turn of a different game.
        if selected != nil { self.chosenGameID = nil }
        // Decoded once per change, not once per redraw.
        self.receivedHeader = try? MatchMessage.header(from: selected)
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
        store.receivedHeader?.game ?? store.chosenGameID
    }

    /// Named `gameBody`, not `body(forGame:)`: a `View` already has a
    /// `body`, and a second thing of that name in the same type is a
    /// confusion waiting for whoever reads it next.
    @ViewBuilder
    private func gameBody(_ id: String?) -> some View {
        if let id {
            MessagesGameRouter(store: store, gameID: id)
        } else if store.selected != nil {
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
            store.chosenGameID = entry.id
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
