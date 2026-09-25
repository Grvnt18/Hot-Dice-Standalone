import SwiftUI

/// The highlight that makes a flat piece read as a lit object.
///
/// The dice in the tray are `.blinn` with `specular` at 0.45 — they read
/// as polished resin because they carry a real highlight (see
/// `DieMaterialFactory`). Nothing drawn in 2D had an equivalent, so a
/// placed die beside a tumbling one read as a sticker beside an object.
///
/// Two things make the difference, and they only work as a pair: a
/// highlight across the upper part of the shape falling off to nothing,
/// and a matching shade at the lower edge. The highlight alone reads as a
/// stripe; the shade alone reads as dirt. Together they are what turns a
/// flat circle into a dome and a flat square into a bevel.
///
/// **One constant decides the direction.** The scene's key light is
/// pitched 60° with a 30° yaw, but its on-screen direction cannot be
/// worked out reliably without a renderer — SceneKit's euler order and the
/// top-down camera both bear on it. So the light is taken to come from
/// above, which is what every 2D shadow in this app already assumes (the
/// hub's was offset `y: 2`), and `litFromTop` is a single line to flip if
/// the device disagrees.
enum PieceSheen {

    /// Where the light comes from. See the note above.
    static let litFromTop = true

    /// How bright the lit edge goes, and how dark the far one.
    ///
    /// Deliberately modest: this has to survive being applied to every
    /// colourway in the palette, including the near-white ones where a
    /// strong highlight blows out and the near-black ones where a strong
    /// shade turns to a hole.
    static let highlight: Double = 0.28
    static let shade: Double = 0.20

    /// The stops, from the lit edge to the far one.
    ///
    /// White over the piece rather than a lighter version of its colour:
    /// a white overlay is what a specular highlight is, and it keeps this
    /// independent of whatever colour the piece happens to be.
    ///
    /// Stated once because there are two consumers with different needs —
    /// a `View` overlay for SwiftUI shapes, and a `GraphicsContext`
    /// shading for the pieces Royal UR draws in a `Canvas`.
    static var stops: [Gradient.Stop] {
        [
            .init(color: .white.opacity(highlight), location: 0.0),
            .init(color: .white.opacity(highlight * 0.35), location: 0.22),
            .init(color: .clear, location: 0.52),
            .init(color: .black.opacity(shade * 0.5), location: 0.80),
            .init(color: .black.opacity(shade), location: 1.0)
        ]
    }

    static var gradient: LinearGradient {
        LinearGradient(stops: stops,
                       startPoint: litFromTop ? .top : .bottom,
                       endPoint: litFromTop ? .bottom : .top)
    }

    /// The same sheen for a `Canvas`, over a rect's vertical extent.
    static func shading(in rect: CGRect) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(stops: stops),
            startPoint: CGPoint(x: rect.midX,
                                y: litFromTop ? rect.minY : rect.maxY),
            endPoint: CGPoint(x: rect.midX,
                              y: litFromTop ? rect.maxY : rect.minY)
        )
    }
}

extension View {
    /// Lights this piece the way the dice are lit.
    ///
    /// Clipped to the shape rather than applied to a rectangle behind it,
    /// so a round piece gets a round highlight — the reason this takes the
    /// shape rather than assuming one.
    func pieceSheen<S: Shape>(_ shape: S) -> some View {
        overlay(shape.fill(PieceSheen.gradient))
    }
}
