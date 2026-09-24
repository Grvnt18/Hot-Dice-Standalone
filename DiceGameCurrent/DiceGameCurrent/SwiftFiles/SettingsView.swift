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
    @ViewBuilder private var scopeNote: some View {
        if let gameName {
            Text("Saved for \(gameName). Each game keeps its own.")
                .font(.stackSans(11))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Music", isOn: $sound.musicEnabled)
                        .font(.stackSans(15))
                        .toggleStyle(RoundedSquareToggleStyle(tint: theme.accentColor))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Music Volume")
                            .font(.stackSans(12))
                            .foregroundStyle(.secondary)
                        TriangleSlider(value: $sound.musicVolume, tint: theme.accentColor)
                    }
                    // Dimmed rather than removed when music is off — a
                    // control that vanishes makes the form jump around and
                    // hides that the setting still exists.
                    .opacity(sound.musicEnabled ? 1 : 0.4)
                    .disabled(!sound.musicEnabled)

                    // tag(nil as Int?) is required: the selection binding is
                    // Int?, and a plain tag(nil) can't infer that, which
                    // silently breaks matching for the Shuffle row.
                    //
                    // .menu style (rather than the Form default, a
                    // navigation-link push to a separate list screen) shows
                    // the current track title inline and in the ambient
                    // tint color automatically — the default style's
                    // collapsed-row preview text ignores a row Text's own
                    // .foregroundStyle, so that alone wasn't enough to make
                    // the title track the slider's color; this style
                    // doesn't have that problem. Per-row foregroundStyle
                    // stays too, for the destination list this style still
                    // has for choosing a different track.
                    Picker("Track", selection: $sound.selectedTrackIndex) {
                        Text("Shuffle").font(.stackSans(14)).foregroundStyle(theme.accentColor).tag(nil as Int?)
                        ForEach(Array(SoundEngine.tracks.enumerated()), id: \.offset) { idx, track in
                            Text(track.displayName).font(.stackSans(14)).foregroundStyle(theme.accentColor).tag(idx as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.stackSans(15))
                    .opacity(sound.musicEnabled ? 1 : 0.4)
                    .disabled(!sound.musicEnabled)
                } header: {
                    Text("Music").font(.stackSans(12))
                } footer: {
                    scopeNote
                }

                Section {
                    Toggle("Sound Effects", isOn: $sound.sfxEnabled)
                        .font(.stackSans(15))
                        .toggleStyle(RoundedSquareToggleStyle(tint: theme.accentColor))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Effects Volume")
                            .font(.stackSans(12))
                            .foregroundStyle(.secondary)
                        TriangleSlider(value: $sound.sfxVolume, tint: theme.accentColor)
                    }
                    .opacity(sound.sfxEnabled ? 1 : 0.4)
                    .disabled(!sound.sfxEnabled)

                } header: {
                    Text("Sound Effects").font(.stackSans(12))
                }

                Section {
                    ColorwayPicker(theme: theme)
                        .padding(.vertical, 4)
                } header: {
                    Text("Table Color").font(.stackSans(12))
                } footer: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Changes the playing surface and this menu's own accent color.")
                        scopeNote
                    }
                    .font(.stackSans(11))
                }

                if !rules.isEmpty {
                    Section {
                        Button {
                            showingHowToPlay = true
                        } label: {
                            Text("How to Play")
                                .font(.stackSans(15))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .tint(theme.accentColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A principal toolbar item rather than .navigationTitle —
                // navigationTitle renders with the system nav-bar font and
                // won't accept a custom face, so the title would have been
                // the one piece of this screen still in the system font.
                ToolbarItem(placement: .principal) {
                    Text("Settings").font(.stackSans(17))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.stackSans(15))
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: ControlShape.cornerRadius))
                        // Tinted HERE, not only on the Form below. Toolbar
                        // content is hoisted into the navigation bar, which
                        // sits outside the Form's view tree — so the
                        // container's .tint never reached this button and
                        // it stayed system blue while everything under it
                        // followed the chosen colour.
                        .tint(theme.accentColor)
                }
            }
            .sheet(isPresented: $showingHowToPlay) {
                HowToPlayView(gameName: gameName, tagline: tagline, sections: rules)
            }
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
private struct HowToPlayView: View {
    let gameName: String?
    let tagline: String?
    let sections: [GameRuleSection]

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = AppTheme.shared

    var body: some View {
        NavigationStack {
            Form {
                // The one-line pitch, ahead of the rules that explain it.
                // These lines were written for the hub tiles and lost their
                // home when the tiles went square and icon-led; this is
                // where a newcomer actually wants them — the shape of the
                // game before the detail of it.
                if let tagline, !tagline.isEmpty {
                    Section {
                        Text(tagline)
                            .font(.stackSans(14))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(sections) { section in
                    Section {
                        Text(section.body)
                            .font(.stackSans(14))
                    } header: {
                        Text(section.title).font(.stackSans(12))
                    }
                }
            }
            .tint(theme.accentColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Named so it is obvious which game's rules these are,
                    // now that the sheet is reachable from more than one.
                    Text(gameName.map { "\($0) — How to Play" } ?? "How to Play")
                        .font(.stackSans(17))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.stackSans(15))
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: ControlShape.cornerRadius))
                        // Tinted HERE, not only on the Form below. Toolbar
                        // content is hoisted into the navigation bar, which
                        // sits outside the Form's view tree — so the
                        // container's .tint never reached this button and
                        // it stayed system blue while everything under it
                        // followed the chosen colour.
                        .tint(theme.accentColor)
                }
            }
        }
    }
}
