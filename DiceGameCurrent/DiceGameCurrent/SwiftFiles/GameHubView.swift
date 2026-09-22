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
        // The width is measured rather than negotiated.
        //
        // The tiles used to be `.aspectRatio(1, contentMode: .fit)` around a
        // resizable image with `maxHeight: .infinity`. That image has no
        // ideal height to offer, so the square had nothing to size itself
        // from but the name label underneath, and every tile collapsed to a
        // postage stamp with an unreadable icon in it. Asking SwiftUI to
        // infer a square from content that is happy at any size is the bug;
        // handing it a number is the fix.
        //
        // The reader sits OUTSIDE the ScrollView on purpose. Inside one it
        // would report the scroll content's height, not the screen's, and
        // a GeometryReader in a scrolling stack takes all the space and
        // breaks the scroll.
        GeometryReader { geo in
            let side = Self.tileSide(forWidth: geo.size.width)

            ZStack {
                // Same timber as every game's header and footer — the hub
                // should read as part of the same object, not a launcher
                // bolted onto the front.
                WoodTiledBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        title(width: geo.size.width)

                        LazyVGrid(columns: Self.columns(forWidth: geo.size.width), spacing: Self.columnGap) {
                            ForEach(GameCatalog.all) { entry in
                                GameTile(entry: entry, side: side, accent: theme.accentColor) {
                                    SoundEngine.shared.play(.buttonTap)
                                    openGame = entry
                                }
                            }
                        }
                        .padding(.horizontal, Self.gutter)
                    }
                    .padding(.vertical, 22)
                }
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

    // MARK: Geometry

    /// Space either side of the grid.
    static let gutter: CGFloat = 16

    /// Space between the two columns.
    static let columnGap: CGFloat = 14

    /// The tile size the layout aims for, before it is fitted to the width.
    ///
    /// Roughly a thumb's width. Everything else follows from it: the column
    /// count is however many of these fit, and the actual side is that
    /// count divided back into the real width.
    static let targetTile: CGFloat = 180

    /// How many columns a given width should carry.
    ///
    /// Two at the bottom, because one column of giant tiles is a list, not a
    /// grid; five at the top, because past that the name under each icon
    /// stops being readable. An iPad gets more games per screen rather than
    /// bigger ones — which is the difference between filling a screen and
    /// scaling to it.
    static func columnCount(forWidth width: CGFloat) -> Int {
        let usable = width - gutter * 2 + columnGap
        let fits = Int(usable / (targetTile + columnGap))
        return min(max(fits, 2), 5)
    }

    /// The square each tile occupies, for a given width.
    ///
    /// The floor matters: a GeometryReader reports a width of zero on its
    /// first pass, and a tile of zero is how the icons vanished before.
    static func tileSide(forWidth width: CGFloat) -> CGFloat {
        let count = CGFloat(columnCount(forWidth: width))
        let available = width - gutter * 2 - columnGap * (count - 1)
        return max(120, available / count)
    }

    /// Fixed rather than flexible now that the side is known: a fixed column
    /// and a fixed tile cannot disagree about the width, which is what left
    /// the old layout negotiating a size neither side had an opinion about.
    static func columns(forWidth width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.fixed(tileSide(forWidth: width)), spacing: columnGap),
              count: columnCount(forWidth: width))
    }

    private func title(width: CGFloat) -> some View {
        // The suite's own mark above its name. The die stands for the app
        // as a whole rather than for any one game, so the hub is the one
        // screen that should carry it — and the one with room for the
        // artwork and the wordmark both.
        //
        // This is NOT the iOS home-screen icon: there is no asset catalog
        // here, so that is set in Swift Playgrounds' project settings.
        VStack(spacing: 6) {
            GameIconView(id: "app")
                // Proportional, like the tiles, so the mark keeps its
                // weight against them on a phone and on an iPad alike.
                .frame(width: Self.headerMark(forWidth: width),
                       height: Self.headerMark(forWidth: width))

            ScriptText("Rolls", size: 52)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        }
    }

    /// The suite mark above the wordmark, bounded at both ends: big enough
    /// to read on a phone, not so big it dwarfs the grid on an iPad.
    static func headerMark(forWidth width: CGFloat) -> CGFloat {
        min(max(width * 0.22, 72), 120)
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

    /// The square this tile fills, measured by the hub rather than inferred.
    let side: CGFloat

    let accent: Color
    let action: () -> Void

    /// Inset from the tile edge to the artwork.
    private static let inset: CGFloat = 10

    /// Space between the icon and the name.
    private static let gap: CGFloat = 6

    /// Room for the name: two lines of Stack Sans at 13pt.
    private static let labelHeight: CGFloat = 34

    /// What is left for the artwork once the name has its room.
    ///
    /// Everything above is a constant, so this is the whole reason the icon
    /// is now legible: it is a stated fraction of a known square rather than
    /// whatever a resizable image could negotiate out of a stack that had no
    /// height to give it.
    static func iconSide(tile: CGFloat) -> CGFloat {
        max(40, tile - inset * 2 - labelHeight - gap)
    }

    var body: some View {
        Button(action: action) {
            // The icon carries the tile and the name sits under it. The
            // tagline is dropped rather than squeezed: on a square tile at
            // phone width there is room for artwork or for a sentence, and
            // the artwork says more.
            VStack(spacing: Self.gap) {
                GameIconView(id: entry.id)
                    .frame(width: Self.iconSide(tile: side),
                           height: Self.iconSide(tile: side))

                Text(entry.displayName)
                    .font(.stackSans(13))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    // Stack Sans overhangs its advance width, so a trailing
                    // glyph can clip against a tight frame.
                    .padding(.trailing, 3)
                    .frame(height: Self.labelHeight)
            }
            // The square comes from the hub's measurement of the screen, so
            // every tile in a row is identical by construction rather than
            // by agreement.
            .frame(width: side, height: side)
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
