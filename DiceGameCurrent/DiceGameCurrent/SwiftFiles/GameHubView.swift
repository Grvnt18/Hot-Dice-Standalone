import SwiftUI

/// The suite's front door: a grid of game tiles, wrapped in the same wood
/// the games themselves use.
///
/// This is now the app's root (see `DiceGameApp`), replacing the hardcoded
/// `DiceGameScreen()`. All eleven games are playable, so every tile opens
/// something — the greyed-out "soon" state the grid carried while the
/// suite was being built has been removed rather than left unreachable.
struct GameHubView: View {

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
            ZStack {
                // Same timber as every game's header and footer — the hub
                // should read as part of the same object, not a launcher
                // bolted onto the front.
                WoodTiledBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        HubTitle(width: geo.size.width)

                        // Says what is absent rather than letting four
                        // separate features fail quietly — see BundleCheck.
                        if let missing = BundleCheck.summary {
                            Text(missing)
                                .font(.poppins(12))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color(hex: "#7A1F1F").opacity(0.92),
                                            in: RoundedRectangle(
                                                cornerRadius: ControlShape.cornerRadius))
                                .padding(.horizontal, HubLayout.gutter)
                        }

                        LazyVGrid(columns: HubLayout.columns(forWidth: geo.size.width),
                                  spacing: HubLayout.columnGap) {
                            ForEach(GameCatalog.all) { entry in
                                GameTile(entry: entry,
                                         side: HubLayout.tileSide(forWidth: geo.size.width)) {
                                    SoundEngine.shared.play(.buttonTap)
                                    // The scope is entered HERE, before the
                                    // cover presents, not in the game's own
                                    // onAppear: the scene reads
                                    // AppTheme.floorBaseColor while it is
                                    // being assembled, so a scope entered
                                    // after the view exists would build the
                                    // floor in the previous game's colour.
                                    GameScope.enter(entry.id)
                                    openGame = entry
                                }
                            }
                        }
                        .frame(width: HubLayout.gridWidth(forWidth: geo.size.width))
                        .padding(.horizontal, HubLayout.gutter)
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
                // Back to the hub's own settings on the way out. One place
                // rather than eleven, so a game added later is covered
                // without remembering to do anything.
                .onDisappear { GameScope.leave() }
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

// MARK: - Geometry

/// Where every size on the hub comes from.
///
/// A file-scope enum, like `PlayfieldLayout`, rather than statics on the
/// view. Two reasons, and the second is the one that matters: layout
/// arithmetic is not view state, and a plain top-level type is resolved
/// without the compiler having to reason about the `View` whose `body` is
/// asking — which is what the previous shape, `Self.gutter` inside a
/// ViewBuilder, made it do.
enum HubLayout {

    /// Space either side of the grid.
    static let gutter: CGFloat = 16

    /// Space between the two columns.
    static let columnGap: CGFloat = 14

    /// Two columns, always — the same shape on a phone and an iPad, a
    /// fixed arrangement rather than something that rearranges itself under
    /// you as the window changes. Eleven games is six rows, the last of
    /// them half full.
    static let columnCount = 2

    /// The largest a tile may grow to.
    ///
    /// Without it, two columns on an iPad Pro give 490pt tiles and about a
    /// row and a half per screen, which turns a ten-game grid into a lot of
    /// scrolling. Past roughly this size a bigger square stops adding
    /// legibility and just adds distance between the games.
    static let maxTile: CGFloat = 300

    /// The square each tile occupies, for a given width.
    ///
    /// The floor matters: a GeometryReader reports a width of zero on its
    /// first pass, and a tile of zero is how the icons vanished before.
    static func tileSide(forWidth width: CGFloat) -> CGFloat {
        let available = width - gutter * 2 - columnGap * CGFloat(columnCount - 1)
        return min(maxTile, max(120, available / CGFloat(columnCount)))
    }

    /// How wide the two columns plus their gap actually come to.
    ///
    /// Once the tile hits `maxTile` the grid stops growing with the screen,
    /// so on an iPad it is narrower than the space available. Giving the
    /// grid this exact width lets the VStack around it do the centring,
    /// rather than leaving two fixed columns hanging against one edge.
    static func gridWidth(forWidth width: CGFloat) -> CGFloat {
        let tile = tileSide(forWidth: width)
        return tile * CGFloat(columnCount) + columnGap * CGFloat(columnCount - 1)
    }

    /// Fixed rather than flexible now that the side is known: a fixed column
    /// and a fixed tile cannot disagree about the width, which is what left
    /// the old layout negotiating a size neither side had an opinion about.
    static func columns(forWidth width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.fixed(tileSide(forWidth: width)), spacing: columnGap),
              count: columnCount)
    }

    /// Inset from a tile's edge to its artwork.
    static let inset: CGFloat = 10

    /// Space between a tile's icon and its name.
    static let gap: CGFloat = 6

    /// The name's point size, sized so a typical name spans the artwork
    /// above it rather than sitting under it as a caption.
    ///
    /// Capped, because the tile is capped: past `maxTile` a proportional
    /// size would give an iPad a 38pt game name over a 210pt icon.
    static func labelFont(tile: CGFloat) -> CGFloat {
        min(tile * 0.125, 28)
    }

    /// Room for a tile's name: two lines at `labelFont`.
    ///
    /// Proportional rather than the fixed 34 it was, and that is not
    /// tidiness — `iconSide` is what is left after this, so a band sized
    /// for a 393pt phone starves the artwork on a 320pt one. At 320 the
    /// icon keeps 51% of its tile; fixing the band at two lines of 22pt
    /// would have taken it to 46% and failed the layout check.
    static func labelHeight(tile: CGFloat) -> CGFloat {
        labelFont(tile: tile) * 2.4
    }

    /// The suite mark above the wordmark, bounded at both ends: big enough
    /// to read on a phone, not so big it dwarfs the grid on an iPad.
    static func headerMark(forWidth width: CGFloat) -> CGFloat {
        min(max(width * 0.22, 72), 120)
    }

    /// What is left for the artwork once the name has its room.
    ///
    /// Everything above is a constant, so this is the whole reason the icon
    /// is legible: it is a stated fraction of a known square rather than
    /// whatever a resizable image could negotiate out of a stack that had no
    /// height to give it.
    static func iconSide(tile: CGFloat) -> CGFloat {
        max(40, tile - inset * 2 - labelHeight(tile: tile) - gap)
    }
}

// MARK: - Title

/// The suite's own mark above its name.
///
/// A struct rather than a method on the hub, for the same reason `GameTile`
/// is one: a view that takes a measurement is a view with a property, and
/// it keeps `body` a plain list of subviews instead of a call the
/// type-checker has to resolve mid-expression.
private struct HubTitle: View {
    let width: CGFloat

    var body: some View {
        // The die stands for the app as a whole rather than for any one
        // game, so the hub is the one screen that should carry it — and the
        // one with room for the artwork and the wordmark both.
        //
        // This is NOT the iOS home-screen icon: there is no asset catalog
        // here, so that is set in Swift Playgrounds' project settings.
        VStack(spacing: 6) {
            GameIconView(id: "app")
                // Proportional, like the tiles, so the mark keeps its weight
                // against them on a phone and on an iPad alike.
                .frame(width: HubLayout.headerMark(forWidth: width),
                       height: HubLayout.headerMark(forWidth: width))

            ScriptText("Rolls", size: 52)
                .foregroundStyle(.white)
                .elevated(.lifted)
        }
    }
}

// MARK: - Tile

private struct GameTile: View {
    let entry: GameCatalogEntry

    /// The square this tile fills, measured by the hub rather than inferred.
    let side: CGFloat

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The icon carries the tile and the name sits under it. The
            // tagline is dropped rather than squeezed: on a square tile at
            // phone width there is room for artwork or for a sentence, and
            // the artwork says more.
            VStack(spacing: HubLayout.gap) {
                GameIconView(id: entry.id)
                    .frame(width: HubLayout.iconSide(tile: side),
                           height: HubLayout.iconSide(tile: side))

                Text(entry.tileName)
                    .font(.poppins(HubLayout.labelFont(tile: side), .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    // One size across the grid, with the longest names
                    // shrinking to fit. Scaling every name to fill its own
                    // width instead would leave a page of tiles carrying
                    // visibly different type sizes.
                    .minimumScaleFactor(0.6)
                    // Stack Sans overhangs its advance width, so a trailing
                    // glyph can clip against a tight frame.
                    .padding(.trailing, 3)
                    .frame(height: HubLayout.labelHeight(tile: side))
            }
            // The square comes from the hub's measurement of the screen, so
            // every tile in a row is identical by construction rather than
            // by agreement.
            .frame(width: side, height: side)
            // Nothing is drawn around the tile at all — no fill, no
            // outline, no shadow. The artwork and its name sit on the
            // timber, and the grid's own spacing is what separates one
            // game from the next.
            //
            // **contentShape is now load-bearing.** A Button hit-tests the
            // content it draws, and with no box there is nothing else
            // between the icon and the label for a tap to land on: without
            // this, a tap in a tile's margin falls through to the scroll
            // view. It was belt-and-braces when the tile had a fill; it is
            // the whole belt now.
            .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
        }
        .buttonStyle(.plain)
    }
}
