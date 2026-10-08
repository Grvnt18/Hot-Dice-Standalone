import SwiftUI
import UIKit

/// Audio settings sheet. Observes SoundEngine.shared directly, so every
/// control writes straight through to the live engine (and to UserDefaults
/// via the engine's didSet observers) with no separate "apply" step. Same
/// pattern for AppTheme.shared, which drives the playing-surface color plus
/// this screen's own accent.
struct SettingsView: View {

    /// The game whose rules How to Play should show, if any.
    ///
    /// Nil from the hub, where no game is open — the button is hidden
    /// rather than showing some arbitrary game's rules, which is what it
    /// did when the rules were hardcoded here.
    var gameName: String? = nil
    var tagline: String? = nil
    var rules: [GameRuleSection] = []

    /// Everything a game's settings sheet needs, stated once by the game
    /// itself rather than spelled out at each of the ten call sites.
    ///
    /// Same trick as `GameCatalogEntry.init(_:makeView:)`: the metadata
    /// lives on the SuiteGame conformance, so adding a field here does not
    /// mean editing every screen.
    init<G: SuiteGame>(for game: G.Type) {
        self.gameName = G.displayName
        self.tagline = G.tagline
        // The guide — the whole one. This sheet used to show a shorter
        // array on the grounds that it opens mid-match, which meant the
        // version missing the detail was the version you could reach
        // without leaving the game.
        self.rules = G.rules
    }

    /// The hub's sheet: no game open, so no rules and no How to Play.
    init() {}

    @ObservedObject private var sound = SoundEngine.shared
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingHowToPlay = false

    /// Says whose settings these are.
    ///
    /// The colour and the music are kept per game, so without this a player
    /// who sets a table colour in one game and finds another unchanged has
    /// every reason to read it as a bug rather than as the feature.
    @ViewBuilder private func scopeNote(perGame: Bool) -> some View {
        if let gameName {
            Text(perGame
                 ? "Saved for \(gameName). Each game keeps its own."
                 : "The same in every game.")
                .font(.poppins(11))
        }
    }

    /// Whether music follows the game or the app.
    ///
    /// Mirrored into `@State` because `GameScope.musicIsPerGame` is a
    /// UserDefaults-backed static, which publishes nothing — without this
    /// the toggle would not move when tapped.
    @State private var musicPerGame = GameScope.musicIsPerGame

    /// What the track button reads when it is closed.
    ///
    /// A plain `if let` rather than `selectedTrackIndex.map { ... } ?? "Shuffle"`
    /// on purpose: a closure inside an optional chain inside a view body is
    /// the exact shape that took the Playgrounds build down silently once,
    /// and `tools_qualcheck.py` flags it for that reason. The index is also
    /// range-checked, since `tracks` is a literal that has changed length
    /// before and a stale stored index would otherwise trap.
    private var trackLabel: String {
        if let idx = sound.selectedTrackIndex,
           idx >= 0, idx < SoundEngine.tracks.count {
            return SoundEngine.tracks[idx].displayName
        }
        return "Shuffle"
    }

    var body: some View {
        // No NavigationStack and no Form. Both were the system's own
        // chrome — a grey grouped list under a translucent nav bar — on a
        // screen reached from timber, steel and pixel panels, which made
        // Settings the one surface in the app that looked like a different
        // app. Everything here is built from what the rest of the suite is
        // already built from: WoodTiledBackground, pixelPanel, pixelWell,
        // RoundedSquareToggleStyle, ControlShape and Poppins.
        //
        // The CONTENT is untouched — same sections in the same order, same
        // strings, same bindings, same scope notes. This is paint.
        ZStack {
            WoodTiledBackground(fraction: MenuTimber.fraction).ignoresSafeArea()

            VStack(spacing: 0) {
                MenuHeaderBar(title: "Settings") { dismiss() }

                ScrollView {
                    VStack(spacing: 14) {
                        panel("Music", footer: AnyView(scopeNote(perGame: musicPerGame))) {
                            Toggle("Music", isOn: $sound.musicEnabled)
                                .font(.poppins(15))
                                .toggleStyle(RoundedSquareToggleStyle(tint: theme.accentColor))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Music Volume")
                                    .font(.poppins(12))
                                    .foregroundStyle(MenuInk.dim)
                                TriangleSlider(value: $sound.musicVolume, tint: theme.accentColor)
                            }
                            // Dimmed rather than removed when music is off — a
                            // control that vanishes makes the page jump around
                            // and hides that the setting still exists.
                            .opacity(sound.musicEnabled ? 1 : 0.4)
                            .disabled(!sound.musicEnabled)

                            // A Menu rather than a Picker, because every
                            // built-in picker style draws system chrome the
                            // restyle replaced: .menu is a capsule button,
                            // .segmented a rounded bar. The capsule is drawn
                            // by the picker's OWN button, so no amount of
                            // framing from outside squares it off — the
                            // control has to be the app's own.
                            //
                            // Same nine choices, same order, and the same
                            // side effect: assigning selectedTrackIndex
                            // restarts playback through its didSet, which is
                            // exactly what the selection binding did.
                            //
                            // This also retires the tag(nil as Int?) note —
                            // there is no tag matching left to get wrong.
                            Menu {
                                Button("Shuffle") { sound.selectedTrackIndex = nil }
                                ForEach(Array(SoundEngine.tracks.enumerated()), id: \.offset) { idx, track in
                                    Button(track.displayName) { sound.selectedTrackIndex = idx }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Track")
                                        .font(.poppins(15))
                                        .foregroundStyle(MenuInk.text)

                                    Spacer(minLength: 8)

                                    Text(trackLabel)
                                        .font(.poppins(14))
                                        .foregroundStyle(theme.accentColor)
                                        .lineLimit(1)

                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(MenuInk.dim)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity)
                                .pixelPanel(fill: .solid(MenuInk.panel),
                                            elevation: .resting)
                            }
                            .opacity(sound.musicEnabled ? 1 : 0.4)
                            .disabled(!sound.musicEnabled)
                        }

                        // The hub only. Inside a game this would be a control
                        // that changes what every OTHER game does, which is
                        // exactly the kind of setting people cannot find again
                        // afterwards.
                        if gameName == nil {
                            panel("Music Scope",
                                  footer: AnyView(
                                    Text(musicPerGame
                                         ? "Each game remembers its own track and volume."
                                         : "One track and volume across every game.")
                                        .font(.poppins(11)))) {
                                Toggle("Music Per Game", isOn: $musicPerGame)
                                    .font(.poppins(15))
                                    .toggleStyle(RoundedSquareToggleStyle(tint: theme.accentColor))
                                    .onValueChange(of: musicPerGame) { now in
                                        GameScope.musicIsPerGame = now
                                    }
                            }
                        }

                        panel("Sound Effects") {
                            Toggle("Sound Effects", isOn: $sound.sfxEnabled)
                                .font(.poppins(15))
                                .toggleStyle(RoundedSquareToggleStyle(tint: theme.accentColor))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Effects Volume")
                                    .font(.poppins(12))
                                    .foregroundStyle(MenuInk.dim)
                                TriangleSlider(value: $sound.sfxVolume, tint: theme.accentColor)
                            }
                            .opacity(sound.sfxEnabled ? 1 : 0.4)
                            .disabled(!sound.sfxEnabled)
                        }

                        panel("Table Color",
                              footer: AnyView(
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Changes the playing surface and this menu's own accent color.")
                                    // Always per game, whatever the music is
                                    // set to — a floor is part of a game's look
                                    // in a way a backing track is not.
                                    scopeNote(perGame: true)
                                }
                                .font(.poppins(11)))) {
                            ColorwayPicker(theme: theme)
                                .padding(.vertical, 4)
                        }

                        // The hub only, and only until the Messages
                        // extension exists. The transport is written and
                        // budgeted but cannot be exercised in Playgrounds
                        // any other way — the extension itself needs Xcode
                        // — so this is where a turn gets packed, sent
                        // through the real URL path and read back, on the
                        // device, before any of it reaches a Mac.
                        if rules.isEmpty {
                            panel("Message Payloads",
                                  footer: AnyView(
                                    Text("Each game packs a turn, sends it "
                                         + "through the real URL path and "
                                         + "reads it back. Budget is "
                                         + "\(GameTransport.safeByteBudget) bytes.")
                                        .font(.poppins(11)))) {
                                WirePayloadCheck()
                            }
                        }

                        // Inside a game this opens that game's guide. On the
                        // hub there is no game to explain, so it opens the
                        // whole set as a cluster of bubbles — the one place a
                        // player browsing the suite can read the rules of a
                        // game before deciding to play it.
                        Button {
                            SoundEngine.shared.play(.buttonTap)
                            showingHowToPlay = true
                        } label: {
                            Text(rules.isEmpty ? "How to Play — Every Game" : "How to Play")
                                .font(.poppins(15))
                                .foregroundStyle(theme.accentTextColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
                        }
                        .buttonStyle(.plain)
                        .pixelPanel(fill: .solid(theme.accentColor), elevation: .lifted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
            }
        }
        .sheet(isPresented: $showingHowToPlay) {
            if rules.isEmpty {
                GuideBubbleCluster()
            } else {
                HowToPlayView(gameName: gameName, tagline: tagline,
                              sections: rules)
            }
        }
    }

    /// One titled group of controls, as a pixel panel on the timber.
    ///
    /// The ViewBuilder closure is called ONCE, here, and the result stored
    /// before it reaches any container — the same shape RollbotsScreen's
    /// menuSheet was rewritten into after a non-escaping parameter captured
    /// by a GeometryReader closure failed to compile. There is no
    /// GeometryReader here, but the habit is cheap and the failure is one
    /// tools_qualcheck.py already watches for.
    @ViewBuilder
    private func panel<Content: View>(
        _ title: String,
        footer: AnyView? = nil,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        let rows = content()
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.poppins(12, .semibold))
                .foregroundStyle(MenuInk.dim)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 12) {
                rows
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelPanel(fill: .solid(MenuInk.panel), elevation: .resting)

            if let footer {
                footer
                    .foregroundStyle(MenuInk.dim)
                    .padding(.horizontal, 2)
            }
        }
        .foregroundStyle(MenuInk.text)
    }
}

/// The ink this menu is written in.
///
/// Named rather than scattered, because these three values appear on every
/// panel in both Settings and How to Play, and the whole reason this screen
/// was rebuilt is that it had drifted away from the rest of the app.
enum MenuInk {

    /// A dark wash over the timber, so a panel reads as a plate laid on the
    /// wood rather than as a lighter patch of it. Not opaque: the grain
    /// still shows through, which is what keeps it one surface.
    static let panel = Color.black.opacity(0.42)
    static let text = Color(white: 0.96)
    static let dim = Color(white: 0.96).opacity(0.65)
}

/// The title bar both menus wear, replacing the system navigation bar.
///
/// The old one was a `.toolbar` on a NavigationStack, which carried two
/// problems worth recording. Toolbar content is hoisted out of the view's
/// body, so it never received the container's `.tint` and the Done button
/// stayed system blue while everything below it followed the chosen colour
/// — and `.navigationTitle` renders in the system face and will not take a
/// custom one, which is why the title was already a principal item here.
/// Drawing the bar means neither is a special case any more.
struct MenuHeaderBar: View {
    let title: String
    let onDone: () -> Void

    @ObservedObject private var theme = AppTheme.shared

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.poppins(17, .semibold))
                .foregroundStyle(MenuInk.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Button {
                SoundEngine.shared.play(.buttonTap)
                onDone()
            } label: {
                Text("Done")
                    .font(.poppins(15))
                    .foregroundStyle(theme.accentTextColor)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius * 0.6))
            }
            .buttonStyle(.plain)
            .pixelPanel(fill: .solid(theme.accentColor),
                        elevation: .lifted,
                        radius: ControlShape.cornerRadius * 0.6)
            // Rebuilt when the swatch changes. The old toolbar button relied
            // on .tint, which is published through the environment and does
            // not re-run hoisted toolbar content — the reported "only updates
            // after you close and re-open Settings".
            .id(theme.colorwayIndex)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(WoodTiledBackground(fraction: MenuTimber.fraction))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.45)).frame(height: 2)
        }
    }
}

// MARK: - Table color picker

/// A horizontal bar of tappable color stripes, one per AppTheme.Swatch —
/// styled after the Polaroid logo's row of solid color bands rather than a
/// grid of circles. Scrollable, since 24 swatches don't fit one screen
/// width as fixed-size stripes. Selecting one updates AppTheme.shared
/// immediately, same "no separate apply step" pattern as the audio
/// controls above.
private struct ColorwayPicker: View {
    @ObservedObject var theme: AppTheme

    private let stripeWidth: CGFloat = 26
    private let stripeHeight: CGFloat = 48
    private let selectedExtraHeight: CGFloat = 10
    private let cornerRadius: CGFloat = 5

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(AppTheme.swatches.enumerated()), id: \.offset) { index, swatch in
                    let isSelected = theme.colorwayIndex == index
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            theme.colorwayIndex = index
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color(hex: swatch.hex))
                            .frame(width: stripeWidth, height: isSelected ? stripeHeight + selectedExtraHeight : stripeHeight)
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                            .overlay(alignment: .bottom) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(swatch.isBright ? .black : .white)
                                        .padding(.bottom, 6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                }
            }
            // Bottom-aligned within a fixed-height row: every stripe sits
            // on the same baseline regardless of its own (possibly taller,
            // when selected) height, so the row reads as one continuous
            // bar rather than stripes floating at different levels.
            .frame(height: stripeHeight + selectedExtraHeight, alignment: .bottom)
            .padding(.horizontal, 2)
        }
    }
}

private extension AppTheme.Swatch {
    /// Local to the picker's checkmark contrast — separate from
    /// AppTheme.rollsTextIsDark, which judges the DARKENED floor tone
    /// actually painted on the table, not the raw swatch shown here.
    var isBright: Bool {
        UIColor(hex: hex).relativeLuminance > 0.6
    }
}

// MARK: - How to Play

/// Rules reference, reachable from the settings menu.
///
/// The sections are handed in rather than held here. They used to be a
/// hardcoded array of Rolls' rules, which was fine while Rolls was the
/// whole app and wrong the moment it was not — opening this from Free Roll
/// explained Rolls. Each game now owns its own text via SuiteGame.rules.
///
/// Theme is observed only so this sheet's own Done button matches the same
/// accent color and shape as everything else.
struct HowToPlayView: View {
    let gameName: String?
    let tagline: String?
    let sections: [GameRuleSection]

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = AppTheme.shared

    var body: some View {
        // Same rebuild as Settings above, and for the same reason: a Form in
        // a NavigationStack is the system's grey grouped list, which is not
        // what any other surface in this app is made of. Content unchanged —
        // the tagline, every section in order, the quick-start note.
        ZStack {
            WoodTiledBackground(fraction: MenuTimber.fraction).ignoresSafeArea()

            VStack(spacing: 0) {
                MenuHeaderBar(
                    title: gameName.map { "\($0) — How to Play" }
                        ?? "How to Play"
                ) { dismiss() }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // The one-line pitch, ahead of the rules that explain
                        // it. These lines were written for the hub tiles and
                        // lost their home when the tiles went square and
                        // icon-led; this is where a newcomer actually wants
                        // them — the shape of the game before the detail.
                        if let tagline, !tagline.isEmpty {
                            Text(tagline)
                                .font(.poppins(14))
                                .foregroundStyle(MenuInk.dim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .pixelPanel(fill: .solid(MenuInk.panel), elevation: .resting)
                        }

                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title.uppercased())
                                    .font(.poppins(12, .semibold))
                                    .foregroundStyle(MenuInk.dim)
                                    .padding(.leading, 2)

                                // The document's own lines — bullets,
                                // numbered steps and tables — rather than a
                                // paragraph made out of them.
                                GuideBodyView(body0: section.body)
                                    .padding(12)
                                    .pixelPanel(fill: .solid(MenuInk.panel), elevation: .resting)

                                // A couple of sections carry one or two —
                                // see GuideFigure.
                                ForEach(section.figures, id: \.rawValue) { figure in
                                    GuideFigureView(figure: figure)
                                }
                            }
                        }

                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
            }
        }
    }
}


// MARK: - Message payloads

/// Runs `GameWireCheck` on demand and shows what each game costs.
///
/// On demand rather than on appear: it encodes every game in the suite, and
/// a settings sheet should not do that work for someone who opened it to
/// change the volume.
private struct WirePayloadCheck: View {

    @State private var results: [GameWireCheck.Result] = []
    @ObservedObject private var theme = AppTheme.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                SoundEngine.shared.play(.buttonTap)
                results = GameWireCheck.runAll()
            } label: {
                Text(results.isEmpty ? "Run the check" : "Run it again")
                    .font(.poppins(14))
                    .foregroundStyle(theme.accentTextColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .contentShape(RoundedRectangle(cornerRadius: ControlShape.cornerRadius))
            }
            .buttonStyle(.plain)
            .pixelPanel(fill: .solid(theme.accentColor), elevation: .resting)

            ForEach(results) { result in
                row(result)
            }

            if let worst = results.map(\.bytes).max(), !results.isEmpty {
                Text("Largest turn: \(worst) B of \(GameTransport.safeByteBudget) B")
                    .font(.poppins(11))
                    .foregroundStyle(MenuInk.dim)
            }
        }
    }

    private func row(_ result: GameWireCheck.Result) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(result.ok ? "OK" : "FAIL")
                    .font(.poppins(11, .bold))
                    .foregroundStyle(result.ok ? Color.green : Color.red)
                    .frame(width: 34, alignment: .leading)

                Text(result.game)
                    .font(.poppins(12))
                    .foregroundStyle(MenuInk.text)

                Spacer(minLength: 4)

                Text("\(result.bytes) B")
                    .font(.poppins(12))
                    .foregroundStyle(result.fits ? MenuInk.dim : Color.red)
            }

            // Only when something is wrong. A list of ten passing rows that
            // each explain themselves is a list nobody reads.
            if let failure = result.failure {
                Text(failure)
                    .font(.poppins(10))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
