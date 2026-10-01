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


// ---------------------------------------------------------------------
// The chrome panel lives here rather than in a file of its own. This project is
// assembled by hand in Swift Playgrounds, which does NOT pick up a new
// file by itself — so a copy that never received it fails at every
// reference, with nothing to say the cause is a file list rather than
// the code.
//
// This file already owns the shapes controls are drawn from, so a
// panel and a button belong in it.
// ---------------------------------------------------------------------

/// The frame every piece of in-game chrome wears: flat fill, hard outline,
/// one-step bevel, hard-offset shadow.
///
/// This exists so the restyle is a decision made once rather than forty-seven
/// separately tweaked `RoundedRectangle`s — which is what the app had, and
/// which is how a suite drifts apart without anyone being able to point at the
/// moment it happened. `Elevation` already owns depth and `PieceSheen` already
/// owns the light; this is the third of the trio, and owns the EDGE.
///
/// It deliberately reuses both rather than drawing its own: the bevel is
/// `PieceSheen.bevel`, so a panel turns its corner toward the same light the
/// dice are lit by, and the shadow goes through `.elevated(_:)`, which
/// `tools_cohesion_verify.py` requires anyway.
struct PixelPanel: ViewModifier {

    /// What the panel is made of. Wood panels sit on the tray's timber and
    /// take no fill of their own; solid ones are a flat colour.
    enum Fill {
        case solid(Color)
        case none
    }

    var fill: Fill = .none
    var elevation: Elevation = .resting
    var radius: CGFloat = ControlShape.cornerRadius
    var outline: CGFloat = PixelPanel.outlineWidth
    var bevel: CGFloat = PixelPanel.bevelWidth

    /// Two pixels, not one.
    ///
    /// One is correct for pixel art drawn at its native size and wrong here,
    /// because these panels are laid out in points on a 2x or 3x display: a
    /// 1pt outline lands on a 2- or 3-device-pixel line that the rasteriser
    /// is free to soften at the ends, and the whole effect depends on the
    /// outline being unambiguously hard.
    static let outlineWidth: CGFloat = 2
    static let bevelWidth: CGFloat = 2

    /// Score cells are small — around 30pt across on a phone — so they take a
    /// thinner outline and a tighter corner than a button does. At the full
    /// 2pt the outline is most of the cell.
    static let cellRadius: CGFloat = 2

    /// Near-black, and shared, so every outline in the app is the same one.
    /// Not pure black: against the tray's dark timber a true black outline
    /// disappears into the seams.
    static let outlineColor = Color(red: 0.10, green: 0.07, blue: 0.05)

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background {
                switch fill {
                case .solid(let color): shape.fill(color)
                case .none: Color.clear
                }
            }
            // Bevel inside the outline, so the lit edge reads as the panel's
            // own turned corner rather than as a second border.
            .overlay(shape.inset(by: outline)
                .strokeBorder(PieceSheen.bevel, lineWidth: bevel))
            .overlay(shape.strokeBorder(PixelPanel.outlineColor, lineWidth: outline))
            .clipShape(shape)
            .elevated(elevation)
    }
}

extension View {
    /// Frames this view as a pixel panel.
    ///
    /// The one way to put a chrome edge on anything, the way `.elevated(_:)`
    /// is the one way to put a shadow on it.
    func pixelPanel(fill: PixelPanel.Fill = .none,
                    elevation: Elevation = .resting,
                    radius: CGFloat = ControlShape.cornerRadius) -> some View {
        modifier(PixelPanel(fill: fill, elevation: elevation, radius: radius))
    }

    /// A panel sunk INTO its surface rather than sitting on it — an empty
    /// score cell, a slot waiting to be filled.
    ///
    /// The same parts with the light reversed: the bevel runs dark-over-light
    /// instead of light-over-dark, and there is no shadow, because nothing
    /// below the surface throws one.
    func pixelWell(radius: CGFloat = ControlShape.cornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .overlay(shape.inset(by: PixelPanel.outlineWidth)
                .strokeBorder(PieceSheen.bevel, lineWidth: PixelPanel.bevelWidth)
                .rotationEffect(.degrees(180)))
            .overlay(shape.strokeBorder(PixelPanel.outlineColor.opacity(0.55),
                                        lineWidth: PixelPanel.outlineWidth))
            .clipShape(shape)
    }
}
