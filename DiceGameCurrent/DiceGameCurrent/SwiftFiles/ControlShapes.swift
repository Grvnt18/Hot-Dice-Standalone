import SwiftUI

/// Shared corner radius for controls meant to read as one matched family
/// of "rounded square" shapes — the settings gear button, the Done
/// buttons, the music/effects mute toggles, and the Roll button all use
/// this same radius, rather than the assortment of circles, capsules, and
/// pill-shaped system switches they used before.
enum ControlShape {
    static let cornerRadius: CGFloat = 10
}

/// A toggle rendered as a rounded-square track and thumb — replacing the
/// system's pill-shaped switch for the Music/Sound Effects "master mute"
/// toggles, per request — tinted with the app's current theme color when
/// on rather than the fixed system green.
struct RoundedSquareToggleStyle: ToggleStyle {
    var tint: Color

    private let trackWidth: CGFloat = 46
    private let trackHeight: CGFloat = 28
    private let thumbInset: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()
                RoundedRectangle(cornerRadius: ControlShape.cornerRadius * 0.6)
                    .fill(configuration.isOn ? tint : Color.secondary.opacity(0.3))
                    .frame(width: trackWidth, height: trackHeight)
                    .overlay {
                        let thumbSize = trackHeight - thumbInset * 2
                        // Offset (not alignment) so the thumb's slide
                        // animates smoothly under .animation(value:) below —
                        // alignment changes don't interpolate as reliably.
                        RoundedRectangle(cornerRadius: ControlShape.cornerRadius * 0.35)
                            .fill(.white)
                            .frame(width: thumbSize, height: thumbSize)
                            .offset(x: configuration.isOn
                                ? (trackWidth - thumbSize) / 2 - thumbInset
                                : -(trackWidth - thumbSize) / 2 + thumbInset)
                    }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
    }
}
