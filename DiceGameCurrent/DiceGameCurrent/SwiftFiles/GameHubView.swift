import SwiftUI

/// The suite's front door: a grid of game tiles, wrapped in the same wood
/// the games themselves use.
///
/// This is now the app's root (see `DiceGameApp`), replacing the hardcoded
/// `DiceGameScreen()`. All ten games are playable, so every tile opens
/// something — the greyed-out "soon" state the grid carried while the
/// suite was being built has been removed rather than left unreachable.
struct GameHubView: View {

    @ObservedObject private var theme = AppTheme.shared
    @State private var showingSettings = false
    @State private var openGame: GameCatalogEntry?

    var body: some View {
        ZStack {
            // Same timber as every game's header and footer — the hub
            // should read as part of the same object, not a launcher
            // bolted onto the front.
            WoodTiledBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    title

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(GameCatalog.all) { entry in
                            GameTile(entry: entry, accent: theme.accentColor) {
                                SoundEngine.shared.play(.buttonTap)
                                openGame = entry
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 22)
            }
        }
        .overlay(alignment: .topTrailing) { settingsButton }
        // Matches DiceGameScreen: sizes throughout this app assume a
        // fixed point size, so Dynamic Type is pinned rather than
        // allowed to rescale a layout that was tuned around it.
        .dynamicTypeSize(.large)
        // Full-screen rather than a NavigationStack push. A pushed view
        // gets a navigation bar, and DiceGameScreen derives its square
        // playfield from the height it is handed — a bar would silently
        // reshape the board. This hands each game the whole screen,
        // exactly as it had when it was the root, and the game draws its
        // own back control via onExit.
        .fullScreenCover(item: $openGame) { entry in
            entry.makeView({ openGame = nil })
        }
        .sheet(isPresented: $showingSettings) {
            // No game, so no rules and no How to Play button. Showing some
            // game's rules from the hub would just be arbitrary.
            SettingsView()
        }
        .onAppear {
            // Belt and braces, not a move.
            //
            // Registration also happens at the top of
            // DiceSceneAssembler.assemble(), which is deliberate and stays
            // — see the comment there, and the one in DiceGameApp about
            // why this must NOT go in App.init(). But the assembler only
            // runs when a SceneKit scene is built, so the hub (and any
            // future 2D game) would otherwise fall back to system fonts
            // with no error. registerIfNeeded() is idempotent, so calling
            // it in both places is free.
            AppFonts.registerIfNeeded()
            SoundEngine.shared.startMusic()
        }
    }

    // Two columns. The tiles are squares that carry artwork plus a name, and
    // three across on a phone shrinks the icon to the point where the games
    // stop being tellable apart at a glance.
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var title: some View {
        // The suite's own mark above its name. The die stands for the app
        // as a whole rather than for any one game, so the hub is the one
        // screen that should carry it — and the one with room for the
        // artwork and the wordmark both.
        //
        // This is NOT the iOS home-screen icon: there is no asset catalog
        // here, so that is set in Swift Playgrounds' project settings.
        VStack(spacing: 6) {
            GameIconView(id: "app")
                .frame(width: 84, height: 84)

            ScriptText("Rolls", size: 52)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        }
    }

    private var settingsButton: some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            showingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.75))
                .padding(9)
                .background(
                    Color.black.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                )
        }
        .padding(10)
    }
}

// MARK: - Tile

private struct GameTile: View {
    let entry: GameCatalogEntry
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The icon carries the tile and the name sits under it. The
            // tagline is dropped rather than squeezed: on a square tile at
            // phone width there is room for artwork or for a sentence, and
            // the artwork says more.
            VStack(spacing: 6) {
                GameIconView(id: entry.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(entry.displayName)
                    .font(.stackSans(13))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    // Stack Sans overhangs its advance width, so a trailing
                    // glyph can clip against a tight frame.
                    .padding(.trailing, 3)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            // Square, not a fixed minimum height. The grid's two flexible
            // columns give every tile the same width, so tying height to
            // width makes them identical squares at any screen size —
            // which a minHeight could not, since the tallest label in a row
            // grew its own tile and left the row ragged.
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                    .fill(accent.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                    .stroke(.black.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
    }
}
