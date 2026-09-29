import SwiftUI

/// Shared corner radius for controls meant to read as one matched family
/// of "rounded square" shapes — the settings gear button, the Done
/// buttons, the music/effects mute toggles, and the Roll button all use
/// this same radius, rather than the assortment of circles, capsules, and
/// pill-shaped system switches they used before.
enum ControlShape {
    /// Was 10. A 10pt radius on a 28pt-tall control is most of the way to a
    /// capsule, and a capsule is the one shape pixel art cannot draw — there
    /// is no way to step a curve that shallow without it going to mush. Four
    /// reads as a deliberately clipped corner at every size the app uses.
    static let cornerRadius: CGFloat = 4

    /// Named rather than derived.
    ///
    /// These were `cornerRadius * 0.6` and `* 0.35`, which gave 6 and 3.5 off
    /// the old 10. Off 4 the same ratios give 2.4 and 1.4 — radii small enough
    /// that the rasteriser rounds them to something arbitrary, so the toggle's
    /// track and thumb would stop matching each other for no visible reason.
    /// A ratio that only worked at one base value was never really a ratio.
    static let trackRadius: CGFloat = 3
    static let thumbRadius: CGFloat = 2
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
                RoundedRectangle(cornerRadius: ControlShape.trackRadius)
                    .fill(configuration.isOn ? tint : Color.secondary.opacity(0.3))
                    .frame(width: trackWidth, height: trackHeight)
                    .overlay {
                        let thumbSize = trackHeight - thumbInset * 2
                        // Offset (not alignment) so the thumb's slide
                        // animates smoothly under .animation(value:) below —
                        // alignment changes don't interpolate as reliably.
                        RoundedRectangle(cornerRadius: ControlShape.thumbRadius)
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
