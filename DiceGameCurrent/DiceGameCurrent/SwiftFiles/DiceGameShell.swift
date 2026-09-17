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
        let view = SCNView()
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true // ensures the physics/render loop actually runs continuously
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Guarding on `session == nil` alone is racy: assembly finishes
        // and assigns `session` asynchronously below, so if SwiftUI calls
        // updateUIView again before that assignment lands (plausible
        // during layout settling), the guard would still pass and a
        // second full scene would get assembled on top of the first. The
        // Coordinator's flag is set synchronously, immediately, closing
        // that window — it's not subject to the same async race since
        // nothing here awaits it.
        guard !context.coordinator.hasStartedAssembly else { return }

        // Bounds can legitimately be zero on the first layout pass;
        // assembly is deferred until the view has real dimensions.
        guard uiView.bounds.width > 0, uiView.bounds.height > 0 else { return }

        context.coordinator.hasStartedAssembly = true

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

    /// Low-poly wood backdrop for the header. Uses woodSurface rather
    /// than the general faceted generator — see that function for why
    /// timber needs directional shards instead of equilateral ones.
    ///
    /// 4:1 pixel ratio because this bar is wide and short; a square source
    /// stretched to fit would shear the grain into slivers.
    private static let backdrop = LowPolyTextures.woodSurface(
        baseColor: UIColor(hex: "#8B6039"),
        planks: 5,
        shardsPerPlank: 16,
        pixelSize: 1024,
        pixelHeight: 256,
        seed: 77123
    )

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Score")
                    .font(.stackSans(14))
                    .foregroundStyle(.secondary)
                Text("\(score)")
                    .font(.stackSans(40)) // was 36 — enlarged further alongside the cells
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
        .background(
            // Tiled at the same fraction of the bar's width that a wall
            // tiles the identical texture across the playfield's width
            // (PlayfieldRim.woodTileFraction) — not a single copy stretched
            // to fill the bar. Stretching one copy scaled the header's
            // planks up to bar-width size while the walls kept tiling at
            // their own, much smaller, scale, so the grain jumped to a
            // visibly different size right at the seam between the two.
            // Tiling both at the same fraction keeps the plank pitch
            // continuous across that seam instead.
            GeometryReader { geo in
                let tileWidth = geo.size.width * CGFloat(PlayfieldRim.woodTileFraction)
                let scale = tileWidth / Self.backdrop.size.width
                Rectangle()
                    .fill(ImagePaint(image: Image(uiImage: Self.backdrop), scale: scale))
            }
        )
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
                .font(.stackSans(17))
                // The die's own paired number color, not a hardcoded
                // white — that made the near-white die (#FCFBF9) show
                // white-on-white and effectively vanish. Each colorway
                // already carries a number color chosen for contrast
                // against its body, so this reuses the same pairing the
                // 3D dice use.
                .foregroundStyle(Color(hex: die.colorway.numberHex))
                .frame(width: width, height: height)
                .background(Color(hex: die.colorway.bodyHex))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [2]))
                .frame(width: width, height: height)
        }
    }
}

// MARK: - Bottom bar (Roll button)

struct DiceRollButton: View {
    let label: String
    let isEnabled: Bool
    let subtitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Button(action: action) {
                Text(label)
                    .font(.stackSans(15))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.stackSans(12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
private struct FireworkBurst: View {
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
private struct FireworksView: View {
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
                    Text(caption)
                        // Aguafina, and NOT uppercased — the screen-wide
                        // .textCase(.uppercase) would otherwise flatten the
                        // script's lowercase forms, which is most of what
                        // gives it its character.
                        .font(.aguafina(score >= 20 ? 46 : 68))
                        .textCase(nil)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.4)
                        .lineLimit(2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                }

                Text("\(score)")
                    .font(.stackSans(220))
                    .minimumScaleFactor(0.05)
                    .lineLimit(1)
                    .foregroundStyle(.white)
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
    @StateObject private var ui = GameUIState()
    @State private var session: DiceGameSession?
    @State private var finishedScore: Int?
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase


    var body: some View {
        ZStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    DiceScoreBar(
                        score: ui.score,
                        bankedOrder: ui.bankedOrder
                    )
                    .frame(height: geo.size.height * 0.15) // back to 0.15 — the rectangular-cell redesign delivers the size increase without needing more vertical space

                    DiceSceneView(
                        session: $session,
                        onSessionCreated: { newSession in
                            // Wired here, synchronously with session
                            // creation — not via a separate .onChange
                            // watching session's nil-ness, which left a
                            // real gap that was the actual cause of the
                            // "cells only fill after tapping again" bug.
                            let controller = newSession.turnController
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
                        .frame(height: geo.size.height * 0.70)
                        .background(Color.black)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                SoundEngine.shared.play(.buttonTap)
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .padding(9)
                                    .background(Color.black.opacity(0.45), in: Circle())
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
                    .frame(height: geo.size.height * 0.15)
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
        // AppFonts' stackSans/aguafina use the relativeTo: overload of
        // Font.custom so minimumScaleFactor can actually shrink them
        // instead of clipping their last glyph (see AppFonts.swift), which
        // as a side effect makes them respond to the system's Dynamic Type
        // setting. Every size in this app was chosen assuming a fixed
        // point size, so that's pinned back to the default here.
        .dynamicTypeSize(.large)
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            SoundEngine.shared.startMusic()
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

// MARK: - Color hex helper (SwiftUI Color, not UIColor)

private extension Color {
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
