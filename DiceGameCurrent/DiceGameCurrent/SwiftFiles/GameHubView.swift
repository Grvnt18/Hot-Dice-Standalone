import SwiftUI

/// The suite's front door: a grid of game tiles, wrapped in the same wood
/// the games themselves use.
///
/// This is now the app's root (see `DiceGameApp`), replacing the hardcoded
/// `DiceGameScreen()`. Games it cannot open yet are still listed, greyed
/// out — showing eight tiles with six marked "soon" says what the suite is
/// going to be, which hiding them would not.
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
                                guard entry.isAvailable else { return }
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
            entry.makeView?({ openGame = nil })
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

    // Two columns: the tiles need room for a name plus a tagline, and three
    // across on a phone leaves the tagline unreadable.
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var title: some View {
        ScriptText("Rolls", size: 52)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
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
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.displayName)
                    .font(.stackSans(17))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    // Aguafina and Stack Sans both overhang their advance
                    // width, so a trailing glyph can clip against a tight
                    // frame — the same problem the score caption hit. Room
                    // on the right rather than a scale factor.
                    .padding(.trailing, 4)

                Text(entry.tagline)
                    .font(.stackSans(11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if !entry.isAvailable {
                    Text("Soon")
                        .font(.stackSans(10))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Color.black.opacity(0.35),
                            in: Capsule()
                        )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                    .fill(accent.opacity(entry.isAvailable ? 0.92 : 0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                    .stroke(.black.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!entry.isAvailable)
        // The dimmed fill already reads as unavailable; this stops
        // VoiceOver announcing a coming-soon tile as a live button.
        .accessibilityHint(entry.isAvailable ? "" : "Not available yet")
    }
}
