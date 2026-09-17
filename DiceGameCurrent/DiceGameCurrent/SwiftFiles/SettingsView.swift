import SwiftUI
import UIKit

/// Audio settings sheet. Observes SoundEngine.shared directly, so every
/// control writes straight through to the live engine (and to UserDefaults
/// via the engine's didSet observers) with no separate "apply" step. Same
/// pattern for AppTheme.shared, which drives the playing-surface color plus
/// this screen's own accent.
struct SettingsView: View {
    @ObservedObject private var sound = SoundEngine.shared
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingHowToPlay = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Music", isOn: $sound.musicEnabled)
                        .font(.stackSans(15))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Music Volume")
                            .font(.stackSans(12))
                            .foregroundStyle(.secondary)
                        TriangleSlider(value: $sound.musicVolume, tint: theme.accentColor, label: "Volume")
                    }
                    // Dimmed rather than removed when music is off — a
                    // control that vanishes makes the form jump around and
                    // hides that the setting still exists.
                    .opacity(sound.musicEnabled ? 1 : 0.4)
                    .disabled(!sound.musicEnabled)

                    // tag(nil as Int?) is required: the selection binding is
                    // Int?, and a plain tag(nil) can't infer that, which
                    // silently breaks matching for the Shuffle row.
                    Picker("Track", selection: $sound.selectedTrackIndex) {
                        Text("Shuffle").font(.stackSans(14)).tag(nil as Int?)
                        ForEach(Array(SoundEngine.tracks.enumerated()), id: \.offset) { idx, track in
                            Text(track.displayName).font(.stackSans(14)).tag(idx as Int?)
                        }
                    }
                    .font(.stackSans(15))
                    .opacity(sound.musicEnabled ? 1 : 0.4)
                    .disabled(!sound.musicEnabled)
                } header: {
                    Text("Music").font(.stackSans(12))
                }

                Section {
                    Toggle("Sound Effects", isOn: $sound.sfxEnabled)
                        .font(.stackSans(15))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Effects Volume")
                            .font(.stackSans(12))
                            .foregroundStyle(.secondary)
                        TriangleSlider(value: $sound.sfxVolume, tint: theme.accentColor, label: "Volume")
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
                    Text("Changes the playing surface and this menu's own accent color.")
                        .font(.stackSans(11))
                }

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
                }
            }
            .sheet(isPresented: $showingHowToPlay) {
                HowToPlayView()
            }
        }
    }
}

// MARK: - Table color picker

/// A grid of tappable swatches, one per AppTheme.Swatch — the current
/// green plus 11 alternates chosen to stay clear of the dice's own colors
/// (see AppTheme.swatches). Selecting one updates AppTheme.shared
/// immediately, same "no separate apply step" pattern as the audio
/// controls above.
private struct ColorwayPicker: View {
    @ObservedObject var theme: AppTheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(AppTheme.swatches.enumerated()), id: \.offset) { index, swatch in
                Button {
                    theme.colorwayIndex = index
                } label: {
                    Circle()
                        .fill(Color(hex: swatch.hex))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .overlay {
                            if theme.colorwayIndex == index {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(swatch.isBright ? .black : .white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
            }
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

/// Rules reference, reachable from the settings menu. Static content — no
/// state to observe — so a plain sheet with its own NavigationStack is all
/// this needs.
private struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(title: String, body: String)] = [
        ("The Pool", "You start with 15 dice: twelve 6-sided, one 8-sided, one 10-sided, and one 12-sided."),
        ("Rolling", "Tap Begin to roll every die still in the pool. Tap any settled die to select it, then tap Roll again to bank your selection and re-roll everything left."),
        ("Scoring", "Lower is better. Banking a die scores it against its own best face: its highest number scores 0, and every face below that costs one point per step down — except a 1, which always costs the die's full number of sides, its worst possible result."),
        ("Banking", "You must bank at least one die from a roll before rerolling the rest. Selecting every remaining die turns the Roll button into Finish — confirming then banks everything and ends the turn."),
        ("Winning", "The game ends once every die has been banked. Add up the points from every die you banked — the lowest total wins.")
    ]

    var body: some View {
        NavigationStack {
            Form {
                ForEach(sections, id: \.title) { section in
                    Section {
                        Text(section.body)
                            .font(.stackSans(14))
                    } header: {
                        Text(section.title).font(.stackSans(12))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("How to Play").font(.stackSans(17))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.stackSans(15))
                }
            }
        }
    }
}
