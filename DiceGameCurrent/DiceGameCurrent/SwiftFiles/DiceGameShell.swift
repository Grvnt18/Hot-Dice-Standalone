import SwiftUI
import SceneKit
import Combine

// MARK: - SCNView wrapper

struct DiceSceneView: UIViewRepresentable {
    @Binding var session: DiceGameSession?
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
        let view = LayoutReportingSCNView()
        // Never black. If any sliver of backdrop is ever visible — an aspect
        // ratio the overscanned floor somehow does not cover, a frame during
        // rotation, the instant before assembly finishes — it should read as
        // part of the field rather than as a hole punched in it.
        view.backgroundColor = SmokeFloor.backdrop(from: AppTheme.shared.floorBaseColor)
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true // ensures the physics/render loop actually runs continuously
        return view
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
        guard !coordinator.hasStartedAssembly else { return }

        // Bounds can legitimately be zero on the first layout pass.
        guard uiView.bounds.width > 0, uiView.bounds.height > 0 else { return }

        coordinator.hasStartedAssembly = true

        let newSession = DiceSceneAssembler.assemble(
            into: uiView
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

/// Tiles HeaderFooterWood.image at the same fraction of its own width that
/// the 3D side/end walls tile their identical wood texture across the
/// playfield (PlayfieldRim.woodTileFraction). Using the SAME source image
/// at the SAME relative scale in the header, the walls, and the footer is
/// what makes them read as one continuous piece of timber wrapping the
/// whole screen — from the header, down the sides, to the Roll button —
/// rather than three separately-styled panels that merely resemble each
/// other.
struct WoodTiledBackground: View {
    var body: some View {
        GeometryReader { geo in
            let tileWidth = geo.size.width * CGFloat(PlayfieldRim.woodTileFraction)
            let scale = tileWidth / HeaderFooterWood.image.size.width
            Rectangle()
                .fill(ImagePaint(image: Image(uiImage: HeaderFooterWood.image), scale: scale))
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
                    .font(.poppins(14))
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

    @ViewBuilder
    private func cell(at index: Int, width: CGFloat, height: CGFloat) -> some View {
        if index < bankedOrder.count {
            let die = bankedOrder[index]
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
                // gets the panel treatment the rest of the chrome has.
                .pixelPanel(fill: .solid(Color(hex: die.colorway.bodyHex)),
                            elevation: .piece,
                            radius: PixelPanel.cellRadius)
        } else {
            // An empty slot is a hole in the panel, not a thing on it, so the
            // light runs the other way — see .pixelWell. The hairline dashed
            // border this replaces was the one piece of chrome that could not
            // survive the restyle: a 0.5pt dashed stroke is sub-pixel on every
            // device the app runs on, which is the opposite of pixel art.
            Color.clear
                .frame(width: width, height: height)
                .pixelWell(radius: PixelPanel.cellRadius)
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
        VStack(spacing: 2) {
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
                    .font(.poppins(12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { i in
                let angle = (Double(i) / Double(particleCount)) * 2 * .pi
                // Varying the reach per particle stops the burst reading as
                // a perfect ring, which looks mechanical rather than
                // explosive.
                let reach: CGFloat = 70 + CGFloat((i * 37) % 55)
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .offset(
                        x: cos(angle) * reach * progress,
                        // Slight downward bias as the burst expands, so
                        // particles arc under gravity instead of floating.
                        y: sin(angle) * reach * progress + (progress * progress * 26)
                    )
                    .opacity(Double(1 - progress))
                    .scaleEffect(1 - progress * 0.55)
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
                        .frame(height: sceneHeight)
                        .background(SmokeFloor.backdropColor)
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
        .onChange(of: theme.colorwayIndex) { _, _ in
            session?.applyTheme()
        }
        // The .playback audio session lets sound continue when the app
        // isn't foreground, which is correct for a game but means nothing
        // stops the music on our behalf. In Playgrounds that showed up as
        // a track outliving the app and appearing to play independently
        // of it. Tie it to scene phase explicitly.
        .onChange(of: scenePhase) { _, phase in
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
            SoundEngine.shared.play(.turnComplete)
            finishedScore = session.turnController.currentScore
        }
    }
}
