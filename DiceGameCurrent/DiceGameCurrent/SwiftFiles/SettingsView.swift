import SwiftUI

/// Audio settings sheet. Observes SoundEngine.shared directly, so every
/// control writes straight through to the live engine (and to UserDefaults
/// via the engine's didSet observers) with no separate "apply" step.
struct SettingsView: View {
    @ObservedObject private var sound = SoundEngine.shared
    @Environment(\.dismiss) private var dismiss

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
                        HStack(spacing: 10) {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                            Slider(value: $sound.musicVolume, in: 0...1)
                                .tint(.green)
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.secondary)
                        }
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
                        HStack(spacing: 10) {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                            Slider(value: $sound.sfxVolume, in: 0...1)
                                .tint(.green)
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .opacity(sound.sfxEnabled ? 1 : 0.4)
                    .disabled(!sound.sfxEnabled)

                } header: {
                    Text("Sound Effects").font(.stackSans(12))
                }
            }
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
        }
    }
}
