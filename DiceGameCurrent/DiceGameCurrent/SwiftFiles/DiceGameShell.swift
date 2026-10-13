import SwiftUI
import SceneKit
import Combine

// MARK: - SCNView wrapper

struct DiceSceneView: UIViewRepresentable {
    @Binding var session: DiceGameSession?

    /// The seed the round is dealt from.
    ///
    /// Defaults to a fresh one, which is the app: every game of Rolls on
    /// this device is its own deal. A Messages match passes the seed that
    /// travelled in the envelope, so every participant rolls the same
    /// fifteen dice — see DiceSceneAssembler.assemble.
    var seed: UInt64 = SeededGenerator.newSeed()
    /// Called synchronously, in the same dispatch block that assigns
    /// `session`, the moment the scene finishes assembling. Replaces an
    /// earlier .onChange(of: session == nil)-based approach that wired
    /// onStateChanged separately, after the fact — that pattern was the
    /// actual cause of a persistent "cells only fill after tapping again"
    /// bug: relying on SwiftUI's change-detection to fire reliably at the
    /// right moment, rather than wiring the callback at the one place that
    /// genuinely knows the session just became ready, left a real gap.
    let onSessionCreated: (DiceGameSession) -> Void

    func makeUIView(context: Context) -> SCNView {
        LayoutReportingSCNView.makeConfigured()
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Re-set on every update, not only at creation, because the backdrop
        // follows the player's table colour. A value assigned once in
        // makeUIView would keep the colour the app launched with and show
        // through as the wrong shade after a swatch change.
        uiView.backgroundColor = SmokeFloor.backdrop(from: AppTheme.shared.floorBaseColor)
        // Re-armed on every update so the closure always writes through to
        // the current binding rather than a stale copy.
        (uiView as? LayoutReportingSCNView)?.onLayout = { view in
            assembleIfReady(view, coordinator: context.coordinator)
        }
        assembleIfReady(uiView, coordinator: context.coordinator)
    }

    /// Builds the scene the first time the view has real dimensions.
    ///
    /// Called from two places, and it needs both. `updateUIView` covers the
    /// case where SwiftUI re-runs the body after layout; `onLayout` covers
    /// the case where it does not.
    ///
    /// That second case is not hypothetical — it was a real bug. Assembly
    /// bails out when bounds are still zero, which is normal on the first
    /// layout pass, and the old code had no way to retry: it simply assumed
    /// SwiftUI would call updateUIView again once the view had a size. As
    /// the app's root view that assumption held. Presented inside a
    /// fullScreenCover from the hub it did not — the view was created and
    /// laid out in one pass with no observed state change afterward, so
    /// updateUIView never ran a second time and the playfield stayed a
    /// blank black box with an unusable Roll button. Opening Settings and
    /// changing the table colour "fixed" it only because
    /// theme.colorwayIndex is @Published, so mutating it re-ran the body
    /// and finally triggered assembly. Reacting to the view actually
    /// gaining bounds removes the guesswork.
    private func assembleIfReady(_ uiView: SCNView, coordinator: Coordinator) {
        // Guarding on `session == nil` alone is racy: assembly finishes
        // and assigns `session` asynchronously below, so if this runs
        // again before that assignment lands (plausible during layout
        // settling, and now also reachable from layoutSubviews), the
        // guard would still pass and a second full scene would get
        // assembled on top of the first. The Coordinator's flag is set
        // synchronously, immediately, closing that window — it's not
        // subject to the same async race since nothing here awaits it.
        // Bounds can legitimately be zero on the first layout pass. Moved
        // above the assembly guard so the shape test below has a size to
        // read; the guard still runs before the flag is set, so the race
        // the note above describes is unchanged.
        guard uiView.bounds.width > 0, uiView.bounds.height > 0 else { return }

        let aspect = PlayfieldLayout.aspect(of: uiView.bounds.size)

        // A view that changed SHAPE since assembly has an arena built for
        // the old one — see PlayfieldLayout.needsRebuild, which also has
        // the measurements. Clearing the flag re-enters assembly below
        // rather than adding a second path into it.
        //
        // This cannot fire on Rolls: its playfield is square at every
        // supported size, so the aspect is 1.0 whatever the window does,
        // and a rebuild here would throw away a round in progress. That is
        // asserted rather than hoped — tools_bandlayout_verify.py.
        if coordinator.hasStartedAssembly,
           PlayfieldLayout.needsRebuild(assembled: coordinator.assembledAspect,
                                        now: aspect) {
            coordinator.hasStartedAssembly = false
        }

        guard !coordinator.hasStartedAssembly else { return }

        coordinator.hasStartedAssembly = true
        coordinator.assembledAspect = aspect

        let newSession = DiceSceneAssembler.assemble(
            into: uiView,
            seed: seed
        )
        DispatchQueue.main.async {
            session = newSession
            onSessionCreated(newSession)
            // No automatic startTurn() here — dice spawn at rest, unrolled,
            // and the player's first Roll tap performs the actual first
            // roll. canConfirmAndRoll already allows pressing Roll with
            // zero selection before any roll has happened this turn.
        }
    }

    final class Coordinator {
        var hasStartedAssembly = false

        /// The aspect ratio the arena in this view was built for.
        ///
        /// On the Coordinator rather than in the view struct because a
        /// UIViewRepresentable is recreated on every SwiftUI update and
        /// the Coordinator is not — the same reason `hasStartedAssembly`
        /// lives here.
        var assembledAspect: Float?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}

/// An SCNView that reports when UIKit lays it out.
///
/// UIViewRepresentable gives no hook for "the view now has real
/// dimensions", and that is precisely the moment scene assembly has been
/// waiting for. The callback takes the view as a parameter rather than
/// capturing it, so the view holding the closure does not create a
/// retain cycle.
final class LayoutReportingSCNView: SCNView {
    var onLayout: ((SCNView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        onLayout?(self)
    }

    /// One configured scene view, for both hosts that make one.
    ///
    /// `DiceSceneView` and `DiceTraySceneView` are deliberately separate —
    /// Rolls wires a turn controller and tap handling, a tray wires
    /// neither — but their `makeUIView` bodies were byte-identical, and
    /// `DiceTraySceneView`'s own comment says the setup is "the part worth
    /// getting identical". Two copies of a thing that must not differ is
    /// the shape that eventually differs: `SceneAntialiasing` and
    /// `SceneRenderScale` are both here because the Simulator aborts
    /// without them, and a third host that forgot one would present as a
    /// blank screen rather than as a mistake.
    static func makeConfigured() -> LayoutReportingSCNView {
        let view = LayoutReportingSCNView()
        // Never black. If any sliver of backdrop is ever visible — an aspect
        // ratio the overscanned floor somehow does not cover, a frame during
        // rotation, the instant before assembly finishes — it should read as
        // part of the field rather than as a hole punched in it.
        view.backgroundColor = SmokeFloor.backdrop(from: AppTheme.shared.floorBaseColor)
        // Off, for the pixel-art edge and because the Simulator aborts on
        // any multisampling — see SceneAntialiasing.
        view.antialiasingMode = SceneAntialiasing.mode
        // Coarse render, magnified with no interpolation — the screen-space
        // pixel grid the dice's drawn edges need to read as lines rather
        // than hairlines. See SceneRenderScale.
        SceneRenderScale.apply(to: view)
        // Keeps the physics and render loop running continuously.
        view.isPlaying = true
        return view
    }
}

// MARK: - Shared header/footer wood backdrop

/// Shared low-poly wood backdrop for the header (DiceScoreBar) and footer
/// (DiceRollButton) — see WoodTiledBackground for why using the exact same
/// image in both places (not just the same generator parameters) matters.
// Internal rather than private: GameHubView wraps itself in the same
// timber, and the point of this type is that every surface shares one
// image instance — a second copy generated from the same parameters would
// tile from a different origin and show a seam.
enum HeaderFooterWood {
    static let image = LowPolyTextures.pixelWood()
}

/// The same thing in steel, for Rollbots.
///
/// Rollbots' arena rim is plate, not timber (ArenaStyle.RimMaterial.steel),
/// and the one-shared-image contract the wood has is exactly as load-bearing
/// here: the rim and any chrome tiled with this must be the SAME UIImage at
/// the SAME fraction, or the join between the 3D rim and the SwiftUI panel
/// above it shows a seam.
enum HeaderFooterSteel {
    static let image = LowPolyTextures.pixelSteel()
}

/// Tiles HeaderFooterWood.image at the same fraction of its own width that
/// the 3D side/end walls tile their identical wood texture across the
/// playfield (PlayfieldRim.woodTileFraction). Using the SAME source image
/// at the SAME relative scale in the header, the walls, and the footer is
/// what makes them read as one continuous piece of timber wrapping the
/// whole screen — from the header, down the sides, to the Roll button —
/// rather than three separately-styled panels that merely resemble each
/// other.
struct WoodTiledBackground: View {

    /// How wide one tile is, as a fraction of the view's width.
    ///
    /// The default is `PlayfieldRim.woodTileFraction`, which is what makes
    /// the header, the walls and the roll button read as one continuous
    /// piece of timber — see above.
    ///
    /// The menus pass a SMALLER one. At the default they showed the same
    /// grain at the same scale as the screen behind them, so a settings panel
    /// read as a window cut through to the background rather than as its own
    /// board. Finer grain is what a smaller board looks like: same timber,
    /// same tones, same image — milled smaller.
    var fraction: Float = PlayfieldRim.woodTileFraction

    var body: some View {
        TiledMaterialBackground(image: HeaderFooterWood.image, fraction: fraction)
    }
}

/// The tile fraction the menus use, so Settings and both guides cannot drift
/// to different grains from each other.
enum MenuTimber {
    static let fraction: Float = 0.30
}

/// The playfield, recessed into the timber it sits in.
///
/// The rolling area used to meet the wood with nothing between them, so it
/// read as a hole cut in the pattern rather than as a well sunk into it. The
/// difference is entirely the lip: `pixelWell` is already the app's "sunk
/// INTO the surface rather than sitting on it" treatment — the bevel runs
/// dark-over-light instead of light-over-dark, and there is no shadow,
/// because nothing below a surface throws one.
///
/// Defined once and applied at eleven call sites rather than written out at
/// each, which is the lesson `OverlayChromeButton` taught when a restyle
/// landed on ten screens and read as a bug on the eleventh.
///
/// `height` is optional because two of the eleven (Baseball Dice and
/// Rollbots) are given their height by a parent rather than setting their
/// own; `nil` leaves the frame unconstrained, which is what those two need.
///
/// `material` exists because ROLLBOTS IS NOT TIMBER. Its `ArenaStyle.steel`
/// gives the 3D rim plate rather than wood, deliberately — "the wooden tray
/// is the wrong object for a duel in the net" — so a timber surround would
/// put the one material that arena rejects directly against its own rim.
/// The well and the rim beside it must be the same stuff, which is the same
/// contract `HeaderFooterWood` and `HeaderFooterSteel` already carry.
enum WellMaterial {
    case timber
    case plate
}

extension View {
    @ViewBuilder
    func rollingWell(height: CGFloat? = nil,
                     material: WellMaterial = .timber,
                     inset: CGFloat = 10) -> some View {
        let lipped = self
            // The backdrop stays directly behind the scene, inside the lip,
            // so a sliver showing during assembly still reads as field
            // rather than as a gap in the surround.
            .background(SmokeFloor.backdropColor)
            .pixelWell(radius: ControlShape.cornerRadius)
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        switch material {
        case .timber:
            lipped.background(WoodTiledBackground()).frame(height: height)
        case .plate:
            lipped.background(SteelTiledBackground()).frame(height: height)
        }
    }
}

/// The steel counterpart, for Rollbots' chrome.
struct SteelTiledBackground: View {
    var fraction: Float = PlayfieldRim.woodTileFraction

    var body: some View {
        TiledMaterialBackground(image: HeaderFooterSteel.image, fraction: fraction)
    }
}

/// The tiling itself, shared so timber and plate cannot drift to different
/// tile fractions — which would be invisible in the diff and obvious on the
/// device, as one screen's rim stopped lining up with its header.
private struct TiledMaterialBackground: View {
    let image: UIImage
    var fraction: Float = PlayfieldRim.woodTileFraction

    var body: some View {
        GeometryReader { geo in
            let tileWidth = geo.size.width * CGFloat(fraction)
            let scale = tileWidth / image.size.width
            Rectangle()
                .fill(ImagePaint(image: Image(uiImage: image), scale: scale))
        }
    }
}

// MARK: - Top bar (score + banked-dice history grid)

struct DiceScoreBar: View {
    let score: Int
    let bankedOrder: [Die]

    private let totalSlots = 15
    // Changed from 5x3 (15 square cells) to 8x2 (16 rectangular slots,
    // one unused) — the actual lever for "bigger cells without more
    // vertical space" was dropping the forced-square constraint, not the
    // row/column count by itself. A cell sized independently by width and
    // height (rather than min() of the two, which always shrinks it down
    // to match whichever dimension is tighter) uses the available space
    // in both directions at once. Fewer rows on top of that means more
    // height per cell too, and a number doesn't need a square cell to
    // read clearly.
    private let gridColumns = 8
    private let gridRows = 2
    private let cellSpacing: CGFloat = 4

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Score")
                    // Semibold, like every other small caption in the two
                    // bands — see TurnActionBar and the roll button's own
                    // subtitle. Regular Poppins at 14 on timber is the one
                    // weight in the app that loses to its background: the
                    // strokes are thinner than the wood grain behind them.
                    .font(.poppins(14, .semibold))
                    .foregroundStyle(.secondary)
                Text("\(score)")
                    .font(.poppins(40, .bold)) // was 36 — enlarged further alongside the cells
            }
            .padding(.trailing, 8)
            .overlay(alignment: .trailing) {
                Divider()
            }

            // GeometryReader here, rather than a plain aspectRatio-driven
            // LazyVGrid, because the previous version sized cells from
            // available WIDTH first (5 columns), which could make each
            // cell taller than the screen space this bar actually has to
            // work with — the grid would then overflow its parent and get
            // clipped top/bottom. Sizing explicitly from the actual
            // available width/height guarantees the whole grid always
            // fits the space it's given, while letting cellWidth and
            // cellHeight differ (rectangular, not forced-square) so both
            // dimensions of the available space actually get used.
            GeometryReader { geo in
                let cellWidth = (geo.size.width - cellSpacing * CGFloat(gridColumns - 1)) / CGFloat(gridColumns)
                let cellHeight = (geo.size.height - cellSpacing * CGFloat(gridRows - 1)) / CGFloat(gridRows)

                // Two explicit centered HStacks rather than a LazyVGrid.
                // With 15 slots in an 8-column grid, the second row holds
                // 7 cells and LazyVGrid left-aligns them, so the bottom
                // row sat flush left under the top row instead of
                // centered. Laying out each row separately lets both be
                // centered independently, which is what makes the shorter
                // bottom row sit symmetrically beneath the full top row.
                VStack(spacing: cellSpacing) {
                    ForEach(0..<gridRows, id: \.self) { row in
                        let start = row * gridColumns
                        let end = min(start + gridColumns, totalSlots)
                        HStack(spacing: cellSpacing) {
                            ForEach(start..<end, id: \.self) { index in
                                cell(at: index, width: cellWidth, height: cellHeight)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WoodTiledBackground())
        // No fade animation here anymore — the 0.25s ease-out was a
        // deliberate polish touch, but it's exactly what was reading as
        // "delay" between confirming a selection and seeing the cell fill.
        // Removed for instant, immediate updates.
    }

    /// Which die, if any, belongs in this slot.
    ///
    /// The last three are RESERVED, one each for the d8, d10 and d12, and
    /// the twelve before them take the d6s in banking order. Without that
    /// the shapes would mean nothing: slots fill in the order dice are
    /// banked, so a d10 banked first would land in a square and the diamond
    /// at the end would sit empty all game.
    private func die(at index: Int) -> Die? {
        let reserved = [8, 10, 12]
        if index >= totalSlots - reserved.count {
            let sides = reserved[index - (totalSlots - reserved.count)]
            return bankedOrder.first { $0.sides == sides }
        }
        var sixes = 0
        for die in bankedOrder where die.sides == 6 {
            if sixes == index { return die }
            sixes += 1
        }
        return nil
    }

    /// The outline this slot wears — its reserved die's face, or a square.
    private func shape(at index: Int) -> DieSlotShape {
        let reserved = [8, 10, 12]
        guard index >= totalSlots - reserved.count else { return .square }
        return DieSlotShape.forSides(reserved[index - (totalSlots - reserved.count)])
    }

    @ViewBuilder
    private func cell(at index: Int, width: CGFloat, height: CGFloat) -> some View {
        if let die = die(at: index) {
            Text("\(die.currentValue ?? 0)")
                .font(.poppins(17, .semibold))
                // The die's own paired number color, not a hardcoded
                // white — that made the near-white die (#FCFBF9) show
                // white-on-white and effectively vanish. Each colorway
                // already carries a number color chosen for contrast
                // against its body, so this reuses the same pairing the
                // 3D dice use.
                .foregroundStyle(Color(hex: die.colorway.numberHex))
                .frame(width: width, height: height)
                // A banked die is a solid thing sitting on the panel, so it
                // gets the panel treatment the rest of the chrome has —
                // cut to its own face for the three that are not d6.
                .background(
                    DieSlot(kind: shape(at: index))
                        .fill(Color(hex: die.colorway.bodyHex))
                )
                // The same three-layer edge every other panel wears, cut
                // to the slot's own shape: a LIT bevel inset inside the
                // outline, then the outline over it. See PixelPanel.body —
                // this is that composition by hand, because a slot is not
                // a rounded rectangle.
                //
                // The bevel is the layer that was never here. The slot had
                // a fill and a flat outline, which is a border; the bevel
                // is what makes an edge read as a turned corner, and it is
                // what the settings button has that this did not.
                .overlay(
                    DieSlot(kind: shape(at: index))
                        .inset(by: PixelPanel.cellOutline)
                        .strokeBorder(PieceSheen.bevel,
                                      lineWidth: PixelPanel.cellBevel)
                )
                .overlay(
                    DieSlot(kind: shape(at: index))
                        .strokeBorder(PixelPanel.outlineColor,
                                      lineWidth: PixelPanel.cellOutline)
                )
                // No shadow, and that is the point of the bevel above.
                //
                // The depth was restored here when the slot read flat, and
                // the shadow turned out to be the wrong half of the fix:
                // the BEVEL is what makes the edge read as a turned corner,
                // and with it in place the offset silhouette behind the
                // slot — and behind the numeral, which is inside the same
                // composite and so cast one too — was the double image
                // rather than the depth.
        } else {
            // An empty slot is a hole in the panel, not a thing on it, so the
            // light runs the other way — see .pixelWell. The hairline dashed
            // border this replaces was the one piece of chrome that could not
            // survive the restyle: a 0.5pt dashed stroke is sub-pixel on every
            // device the app runs on, which is the opposite of pixel art.
            //
            // That comment described two layers and only one was here: a
            // bare `stroke` and no bevel at all. Both halves of the gap
            // showed on the three RESERVED slots and not on the twelve
            // squares, which is why this read as a d8/d10/d12 problem —
            //
            //   * `stroke` centres the line on the path, so half of it
            //     falls OUTSIDE the shape. On a rounded rectangle that is
            //     half a point of overhang nobody sees. On a polygon it is
            //     a mitre: three acute vertices, each throwing a spike well
            //     past the slot it belongs to. `strokeBorder` — which is
            //     what every filled slot already uses, and what `DieSlot`
            //     is an InsettableShape in order to allow — draws the line
            //     wholly inside instead.
            //   * and with no bevel the outline is a border rather than a
            //     turned edge, so a polygon whose only cue is its outline
            //     lost more of its form than a square did.
            //
            // So: the filled slot's composition exactly, with the bevel
            // reversed because this one is sunk. Same shape, same widths,
            // same order — bevel inset inside the outline, outline over it.
            Color.clear
                .frame(width: width, height: height)
                .overlay(
                    DieSlot(kind: shape(at: index))
                        .inset(by: PixelPanel.cellOutline)
                        .strokeBorder(PieceSheen.bevelSunk,
                                      lineWidth: PixelPanel.cellBevel)
                )
                .overlay(
                    DieSlot(kind: shape(at: index))
                        .strokeBorder(PixelPanel.outlineColor.opacity(0.55),
                                      lineWidth: PixelPanel.cellOutline)
                )
        }
    }
}

// MARK: - Bottom bar (Roll button)

struct DiceRollButton: View {
    let label: String
    let isEnabled: Bool
    let subtitle: String
    let action: () -> Void

    /// Observed so the button repaints the moment the colour changes in
    /// Settings, rather than on the next time the screen happens to
    /// rebuild — the sheet is open over this button while you pick.
    @ObservedObject private var theme = AppTheme.shared

    var body: some View {
        // See TurnActionBar: 2pt put the caption inside the 6pt shadow
        // this button throws.
        VStack(spacing: Elevation.lifted.offset + 2) {
            Button(action: action) {
                Text(label)
                    .font(.poppins(15))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    // Load-bearing, not belt-and-braces. `.plain` hit-tests
                    // the DRAWN content, and a Text draws only its glyphs —
                    // a .frame around it is layout, not something to tap. So
                    // without this the bar responded on the word "Roll" and
                    // nowhere else, which is what happened the moment the
                    // style changed.
                    //
                    // `.borderedProminent` used to draw a filled capsule
                    // INSIDE the button, and that fill was what made the
                    // whole bar tappable. The fill now comes from
                    // .pixelPanel applied OUTSIDE the button, where it is
                    // decoration and cannot contribute to hit-testing.
                    //
                    // Same radius as the panel, so the tap target is exactly
                    // the shape the player can see. This is the second time
                    // this bug has shipped — GameHubView's tiles were the
                    // first, when their filled plate was removed — so
                    // tools_cohesion_verify.py now checks for it.
                    .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
            }
            // .plain, not .borderedProminent: the system style draws its own
            // rounded, subtly gradiented capsule and there is no way to stop
            // it, so the panel would be sitting on top of a shape that
            // disagreed with it at every corner. The tint it used to supply
            // is now the panel's fill, which is the same colour doing the
            // same job — the chosen table colour on the largest control on
            // screen, rather than the system blue it defaulted to.
            .buttonStyle(.plain)
            .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.5))
            .pixelPanel(fill: .solid(isEnabled
                                     ? theme.accentColor
                                     : theme.accentColor.opacity(0.4)),
                        elevation: .lifted)
            .disabled(!isEnabled)

            if !subtitle.isEmpty {
                Text(subtitle)
                    // Semibold. This is the line under the roll button —
                    // the selection count, the bust warning, whose turn it
                    // is — and it sits on timber in `.secondary`, which is
                    // already a reduced ink. Regular weight on top of that
                    // was two reductions on the one line in the band that
                    // says what to do next.
                    .font(.poppins(12, .semibold))
                    .foregroundStyle(.secondary)
                    // One line, like TurnActionBar's. Without this it
                    // wraps on a narrow screen and the band it sits in —
                    // sized for one line, see GameBandLayout.captionLine —
                    // has nowhere to put the second.
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Fills the band it is handed, rather than sizing to its own
        // content.
        //
        // Both callers already pass `.frame(height: buttonHeight)`, so
        // this changes nothing on screen — but it moves the guarantee
        // inside the view. Without it the stack sizes to the caption, and
        // the caption now carries `minimumScaleFactor`, which means a
        // sentence would be deciding how far the wood below reaches.
        // tools_cohesion_verify.py fails exactly that, and is right to:
        // a surface does not breathe with a caption.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Same wood as the header, tiled the same way — see
        // WoodTiledBackground. This area grows to absorb whatever height
        // squaring the scene above frees up (see DiceGameScreen.body), so
        // it needed its own backdrop rather than the plain background it
        // had when it was a thin, fixed-height strip: without one, that
        // freed space would just be bare background instead of finishing
        // the wood frame that now runs continuously from the header, down
        // the sides, to here.
        .background(WoodTiledBackground())
    }
}

// MARK: - Turn-complete score reveal

/// Shown when "Finish" banks everything remaining and ends the turn: the
/// final score expands in from small to large over 1.5s, centered, while
/// the rest of the game dims underneath it. Tap anywhere to dismiss —
/// this test shell doesn't yet start a new turn afterward (a real build
/// would show a proper end-of-turn screen or send the iMessage challenge
/// here instead).
/// One firework burst: particles radiating from a point, fading as they go.
struct FireworkBurst: View {
    let origin: CGPoint
    let color: Color
    let delay: Double

    @State private var progress: CGFloat = 0

    private let particleCount = 14

    /// Where particle `i` has travelled to at `t`.
    ///
    /// Out of the ViewBuilder and single-typed, and that is not tidiness.
    /// Swift solves a whole expression at once, weighing every overload of
    /// every operator in it, and mixing Double with CGFloat roughly doubles
    /// the branching at each node because both conform to the protocols the
    /// operators are declared on. This body was fifteen operators and two
    /// trig calls with both numeric types present — the worst expression in
    /// the tree, and Xcode 14.2's solver gave up on it with "unable to
    /// type-check this expression in reasonable time".
    ///
    /// EVERY NUMBER IS THE SAME. cos(angle) * reach * t, the gravity term,
    /// the fade and the shrink are character-for-character what they were;
    /// they are annotated and moved, not rewritten. "Simplify the
    /// expression" is exactly how a burst quietly changes shape.
    private func particleOffset(_ i: Int, t: Double) -> CGSize {
        let angle: Double = (Double(i) / Double(particleCount)) * 2 * .pi
        // Varying the reach per particle stops the burst reading as a
        // perfect ring, which looks mechanical rather than explosive.
        let reach: Double = 70 + Double((i * 37) % 55)
        let x: Double = cos(angle) * reach * t
        // Slight downward bias as the burst expands, so particles arc
        // under gravity instead of floating.
        let y: Double = sin(angle) * reach * t + t * t * 26
        return CGSize(width: x, height: y)
    }

    var body: some View {
        let t: Double = Double(progress)
        let fade: Double = 1 - t
        let shrink: CGFloat = CGFloat(1 - t * 0.55)

        return ZStack {
            ForEach(0..<particleCount, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .offset(particleOffset(i, t: t))
                    .opacity(fade)
                    .scaleEffect(shrink)
            }
        }
        .position(origin)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).delay(delay).repeatForever(autoreverses: false)) {
                progress = 1
            }
        }
    }
}

/// Fireworks layer — several bursts at staggered positions and delays.
///
/// Internal rather than private: MatchResultView uses the same celebration
/// so a win reads the same across the suite.
struct FireworksView: View {
    private let bursts: [(CGPoint, Color, Double)] = [
        (CGPoint(x: 0.24, y: 0.26), .yellow, 0.0),
        (CGPoint(x: 0.76, y: 0.20), .cyan,   0.35),
        (CGPoint(x: 0.50, y: 0.13), .pink,   0.7),
        (CGPoint(x: 0.18, y: 0.62), .green,  1.0),
        (CGPoint(x: 0.82, y: 0.58), .orange, 1.35)
    ]

    var body: some View {
        // Positions are fractions of the container, so bursts land
        // sensibly on any screen size rather than at fixed pixel offsets.
        GeometryReader { geo in
            ForEach(Array(bursts.enumerated()), id: \.offset) { _, b in
                FireworkBurst(
                    origin: CGPoint(x: b.0.x * geo.size.width, y: b.0.y * geo.size.height),
                    color: b.1,
                    delay: b.2
                )
            }
        }
        .allowsHitTesting(false)
    }
}

struct TurnCompleteOverlay: View {
    let score: Int
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.1
    @State private var textOpacity: Double = 0

    /// Lower is better (golf scoring), so the praise bands run from 0 up.
    /// Returns nil where the design calls for no caption at all.
    private var caption: String? {
        switch score {
        case 0:       return "Perfect"
        case 1...3:   return "Excellent"
        case 4...5:   return "Great"
        case 6...10:  return "Good"
        case 11...19: return nil
        default:      return "You're going to need some luck!"
        }
    }

    /// Fireworks are reserved for the top two bands, so they stay a genuine
    /// reward rather than something that fires on every result.
    private var showsFireworks: Bool { score <= 3 }

    var body: some View {
        ZStack {
            // Dims everything underneath by ~75% (leaves ~25% visible)
            // rather than fully hiding it, so the game board is still
            // faintly present behind the score.
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            if showsFireworks {
                FireworksView()
            }

            VStack(spacing: 4) {
                if let caption {
                    // ScriptText rather than a Text with its own font: it
                    // reserves the room Aguafina's swashes need, which this
                    // site used to do by appending two literal spaces to
                    // the string. That worked at one point size and is the
                    // sort of thing a new screen never remembers to copy.
                    //
                    // NOT uppercased — the screen-wide .textCase(.uppercase)
                    // would flatten the script's lowercase forms, which is
                    // most of what gives it its character.
                    // Praise, not information — the score below carries the
                    // meaning, and the caption is deliberately absent in the
                    // middle band. So the short words stay on the script face.
                    //
                    // The 20+ band is the exception, and it is why the size
                    // was already conditional here: it is not a word, it is
                    // the sentence "You're going to need some luck!", which at
                    // minimumScaleFactor 0.4 can land around 18pt across two
                    // lines. That is a sentence to read, so it takes the sans.
                    Group {
                        if score >= 20 {
                            Text(caption)
                                .font(.poppins(46, .medium))
                                .lineLimit(2)
                                .minimumScaleFactor(0.4)
                                .multilineTextAlignment(.center)
                        } else {
                            ScriptText(caption,
                                       size: 68,
                                       lineLimit: 2,
                                       minimumScaleFactor: 0.4)
                        }
                    }
                        .textCase(nil)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                }

                // Trailing spaces, same reasoning as the caption above
                // — Poppins is a plain sans face with much less
                // overhang than a script's swashes, but the
                // minimumScaleFactor(0.05) here is far more extreme, so
                // the same class of advance-width-vs-ink-extent gap is
                // cheap insurance against a repeat of the digit clipping
                // this exact screen originally shipped with.
                Text("\(score)  ")
                    .font(.poppins(220, .black))
                    .minimumScaleFactor(0.05)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    // .frame(maxWidth: .infinity) expands this Text's own
                    // layout box to the full available width, but without
                    // this, Text defaults to LEADING alignment within a
                    // box wider than its content — the digits (plus the
                    // trailing anti-clipping spaces above) sat flush-left
                    // instead of centered, unlike the caption above it
                    // (which does set this).
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
            }
            .scaleEffect(scale)
            .opacity(textOpacity)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            withAnimation(.easeOut(duration: 1.5)) {
                scale = 1.0
                textOpacity = 1.0
            }
        }
    }
}

// MARK: - Root game screen (15% / 70% / 15%)

/// Observable snapshot of everything the 2D UI displays.
///
/// This replaces an earlier `@State private var refreshTick = 0` that was
/// incremented on every state change to "force" a re-render — that was the
/// actual, root cause of ALL THREE long-standing UI bugs (button label
/// stuck on "Begin", subtitle never showing the selection count, and score
/// cells staying empty until the game ended). SwiftUI only re-invokes
/// `body` for state that `body` actually READS, and `refreshTick` was
/// never read anywhere in it — so it was write-only, and SwiftUI correctly
/// optimized it away, scheduling no re-render at all. Adding a timer that
/// incremented it more often (a previous attempt) couldn't help for the
/// same reason.
///
/// It also explains the specific "everything appears correctly at the very
/// end" symptom: `finishedScore` IS read in `body`, so setting it at game
/// end forced the single re-render where all the accumulated state
/// suddenly showed up at once.
///
/// Published properties that body genuinely reads can't fail this way.
final class GameUIState: ObservableObject {
    @Published var score = 0
    @Published var bankedOrder: [Die] = []
    @Published var buttonLabel = "Begin"
    @Published var buttonEnabled = false
    @Published var buttonSubtitle = ""

    /// Pulls current values out of the controller. Called from
    /// turnController.onStateChanged, so the UI updates the instant game
    /// state changes rather than on any polling interval.
    func sync(from turnController: DiceTurnController) {
        score = turnController.currentScore
        bankedOrder = turnController.bankedOrder
        buttonLabel = turnController.rollButtonLabel
        buttonEnabled = turnController.canConfirmAndRoll
        buttonSubtitle = turnController.rollButtonSubtitle
    }
}

struct DiceGameScreen: View {

    /// Dismisses the game and returns to the hub.
    ///
    /// Optional, and nil when DiceGameScreen is the root — which is how it
    /// ran before the hub existed, and how it will run inside a Messages
    /// conversation where Messages supplies its own dismissal. The control
    /// is drawn in the same overlay as the gear rather than in a navigation
    /// bar on purpose: a nav bar consumes vertical space, and this screen
    /// derives its square playfield from the height it is given, so a bar
    /// would quietly reshape the board.
    var onExit: (() -> Void)? = nil

    /// Called once the round is over, with the result packed for sending.
    ///
    /// Nil in the app, where a finished round is a score on an overlay and
    /// nothing more. Set by the Messages extension, which turns it into the
    /// message it inserts into the conversation — so the extension does not
    /// need its own copy of this screen, and this screen does not need to
    /// know a conversation exists.
    ///
    /// `RollsPlayerResult` rather than the round itself: the round is the
    /// controller's to own and mutate, and what travels is already a
    /// separate, Codable type with its own initialiser. See
    /// `DiceTurnController.wireResult`.
    var onRoundFinished: ((RollsPlayerResult) -> Void)? = nil

    /// Called when the player taps the finished-round overlay away.
    ///
    /// Separate from `onRoundFinished`, which fires the instant the last
    /// die is banked — deliberately, so a Messages turn is sent whether
    /// the player dismisses the overlay or walks off. Pass-and-play needs
    /// the other moment: the score and its praise band are the player's
    /// own reward for the round, and a host that advanced on
    /// `onRoundFinished` would replace them with "Pass to <next>" before
    /// they had been read.
    ///
    /// Nil everywhere else, including in the extension, which has nothing
    /// to do at dismissal.
    var onRoundDismissed: (() -> Void)? = nil

    /// The seed this round is dealt from.
    ///
    /// Fresh by default. The Messages extension passes the one carried in
    /// the envelope, which is what makes a conversation's participants
    /// play the same deal rather than fifteen dice each of their own.
    var seed: UInt64 = SeededGenerator.newSeed()

    @StateObject private var ui = GameUIState()
    @State private var session: DiceGameSession?
    @State private var finishedScore: Int?
    @State private var showingSettings = false
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.scenePhase) private var scenePhase


    var body: some View {
        ZStack {
            GeometryReader { geo in
                // The scene is sized SQUARE (its own width) rather than a
                // fixed 70% of the screen's height — DiceSceneAssembler
                // derives the playfield's world bounds directly from this
                // view's own measured aspect ratio, so a square frame here
                // is what makes the actual rolling area square, with no
                // changes needed anywhere in the playfield/physics/camera
                // math itself.
                //
                // minButtonHeight keeps the Roll button's own row from
                // being squeezed away to nothing on a screen short enough
                // (e.g. landscape) that header + a full square scene
                // wouldn't leave room for it — in that case the scene
                // gives up squareness rather than the button giving up
                // usability. Otherwise (the normal portrait case, where
                // 70%-of-height was always taller than the screen is
                // wide), the scene comes out smaller than the old 70%
                // slice, and the space that frees up is added to the
                // button's row rather than removed from the game — see
                // DiceRollButton's own wood backdrop for why that freed
                // space doesn't just become bare background.
                let headerHeight = geo.size.height * 0.15
                let minButtonHeight: CGFloat = 100
                let sceneHeight = min(geo.size.width, max(geo.size.height - headerHeight - minButtonHeight, 0))
                let buttonHeight = geo.size.height - headerHeight - sceneHeight

                VStack(spacing: 0) {
                    DiceScoreBar(
                        score: ui.score,
                        bankedOrder: ui.bankedOrder
                    )
                    .frame(height: headerHeight)

                    DiceSceneView(
                        session: $session,
                        seed: seed,
                        onSessionCreated: { newSession in
                            // Wired here, synchronously with session
                            // creation — not via a separate .onChange
                            // watching session's nil-ness, which left a
                            // real gap that was the actual cause of the
                            // "cells only fill after tapping again" bug.
                            let controller = newSession.turnController
                            // Hopped to the main thread, and that is the
                            // whole bug rather than a precaution.
                            //
                            // This fires from recordSettledValue, which is
                            // called from the onDieSettled callback, which
                            // the roll controller raises inside
                            // renderer(_:updateAtTime:) — SceneKit's RENDER
                            // THREAD. `ui` is observed by this view, so
                            // syncing it there mutated SwiftUI state off the
                            // main thread on every die that settled.
                            //
                            // It survived for a long time because it did
                            // almost nothing. Stage A gave updateUIView real
                            // work to do — reading AppTheme.shared, an
                            // ObservableObject, and writing a UIView
                            // property — and UIKit touched from a background
                            // thread does not raise a Swift error. It
                            // corrupts and dies, with nothing printed, which
                            // is exactly how this presented.
                            //
                            // Only Rolls does this. The other ten games
                            // batch through onRollComplete, which the roll
                            // controller already dispatches to main.
                            // No main-thread hop here any more. It was
                            // right, but it guarded one subscriber against
                            // nine publishers — onStateChanged is raised in
                            // nine places, and FreeRollScreen assigns it
                            // too. The hop now lives where the render thread
                            // actually hands off, in DiceRollController's
                            // onDieSettled, so every consumer is safe by the
                            // same mechanism rather than by remembering.
                            controller.onStateChanged = { [weak controller] in
                                guard let controller else { return }
                                ui.sync(from: controller)
                            }
                            // Initial sync so the button starts in the
                            // correct state rather than its placeholder
                            // default the moment the scene is ready.
                            ui.sync(from: controller)
                        }
                    )
                        .rollingWell(height: sceneHeight)
                        .overlay(alignment: .topLeading) {
                            if let onExit {
                                Button {
                                    SoundEngine.shared.play(.buttonTap)
                                    onExit()
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .padding(9)
                                        // These two float directly over the
                                        // playfield, so they take the field's
                                        // own darkest tone rather than a black
                                        // wash — the same reason nothing else
                                        // behind the tray is black any more.
                                        .pixelPanel(fill: .solid(SmokeFloor.backdropColor.opacity(0.85)),
                                                    elevation: .piece)
                                }
                                .padding(10)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            Button {
                                SoundEngine.shared.play(.buttonTap)
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(9)
                                    .pixelPanel(fill: .solid(SmokeFloor.backdropColor.opacity(0.85)),
                                                elevation: .piece)
                            }
                            .padding(10)
                        }

                    DiceRollButton(
                        label: ui.buttonLabel,
                        isEnabled: ui.buttonEnabled,
                        subtitle: ui.buttonSubtitle
                    ) {
                        rollTapped()
                    }
                    .frame(height: buttonHeight)
                }
            }

            if let finishedScore {
                TurnCompleteOverlay(score: finishedScore) {
                    self.finishedScore = nil
                    onRoundDismissed?()
                }
                .transition(.opacity)
            }
        }
        // Cascades to every Text in this view hierarchy — Stack Sans as
        // the default font is applied per-Text above (font doesn't
        // reliably cascade across custom sizes the same simple way), but
        // uppercase casing genuinely does cascade from one place here.
        .textCase(.uppercase)
        // AppFonts' poppins/lobster use the relativeTo: overload of
        // Font.custom so minimumScaleFactor can actually shrink them
        // instead of clipping their last glyph (see AppFonts.swift), which
        // as a side effect makes them respond to the system's Dynamic Type
        // setting. Every size in this app was chosen assuming a fixed
        // point size, so that's pinned back to the default here.
        .dynamicTypeSize(.large)
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showingSettings) {
            SettingsView(for: RollsGame.self)
        }
        .onAppear {
            SoundEngine.shared.startMusic()
        }
        // Re-paints the already-assembled floor/text materials in place
        // rather than waiting for the next launch, so picking a new table
        // color in Settings is visible the instant the sheet closes.
        .onValueChange(of: theme.colorwayIndex) { _ in
            session?.applyTheme()
        }
        // The .playback audio session lets sound continue when the app
        // isn't foreground, which is correct for a game but means nothing
        // stops the music on our behalf. In Playgrounds that showed up as
        // a track outliving the app and appearing to play independently
        // of it. Tie it to scene phase explicitly.
        .onValueChange(of: scenePhase) { phase in
            switch phase {
            case .active:                SoundEngine.shared.resumeFromForeground()
            case .inactive, .background: SoundEngine.shared.suspendForBackground()
            @unknown default:            break
            }
        }
        // The 0.15s polling timer that used to live here is gone. It was a
        // workaround built on top of the same broken refreshTick mechanism
        // it was meant to compensate for, so it never actually worked —
        // and with GameUIState's @Published properties driving the UI
        // directly, there's nothing left for it to compensate for anyway.
    }

    private func rollTapped() {
        guard let session else { return }
        SoundEngine.shared.play(.buttonTap)
        session.turnController.confirmSelectionAndRoll {
            // No turn-complete sound was supplied, so the cue is gone rather
            // than declared-and-silent. Restore both together when one is.
            finishedScore = session.turnController.currentScore
            // Read before the overlay is dismissed, not after: the player
            // taps that overlay away and the extension needs the result
            // whether they do or not.
            onRoundFinished?(session.turnController.wireResult)
        }
    }
}
