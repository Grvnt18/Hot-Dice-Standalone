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
    /// Three flat bands with hard steps between them, not a ramp.
    ///
    /// Repeating a location is what makes the step hard: the gradient has
    /// nowhere to interpolate across, so it jumps. That is the whole
    /// difference between a lit face and a shaded one, and a soft vertical
    /// wash — which is what this was, five stops smoothly blended, and which
    /// reads as rendered no matter how flat everything around it is.
    ///
    /// Still a gradient rather than three stacked rectangles because both
    /// consumers want one paint: a SwiftUI overlay clipped to an arbitrary
    /// shape, and a `GraphicsContext.Shading` for Royal UR's `Canvas`.
    static var stops: [Gradient.Stop] {
        [
            .init(color: .white.opacity(highlight), location: 0.0),
            .init(color: .white.opacity(highlight), location: 0.30),
            .init(color: .clear, location: 0.30),
            .init(color: .clear, location: 0.68),
            .init(color: .black.opacity(shade), location: 0.68),
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

    /// The bevel: a bright inner edge on the lit side, dark on the far one.
    ///
    /// What the rounded corner of a real die does to the light, and the
    /// second half of reading as solid from an orthographic top-down
    /// camera — which shows no sides at all, so the edge is the only place
    /// the form can show.
    /// Two flat halves, lit above and shadowed below, with one hard step.
    ///
    /// This is the pixel-art bevel: a sprite draws a raised edge as one row
    /// of light and one row of dark, never a fade between them.
    static var bevel: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(highlight * 1.6), location: 0.0),
                .init(color: .white.opacity(highlight * 1.6), location: 0.5),
                .init(color: .black.opacity(shade * 1.4), location: 0.5),
                .init(color: .black.opacity(shade * 1.4), location: 1.0)
            ],
            startPoint: litFromTop ? .top : .bottom,
            endPoint: litFromTop ? .bottom : .top
        )
    }

    /// `bevel` with the light the other way — an edge sunk INTO a surface
    /// rather than standing out of it.
    ///
    /// `pixelWell` reaches the same place by rotating the overlay half a
    /// turn, which works only because a rounded rectangle is its own 180°
    /// rotation. Rolls' empty banking slots are not: a triangle turned
    /// half a turn points at the floor. So the sunk direction has to be a
    /// paint rather than a transform, and this is it — the same two flat
    /// halves and the same hard step, read from the far end.
    ///
    /// Deliberately the same stops as `bevel`, not a second set of
    /// numbers. One bevel with two directions stays one decision; two
    /// gradients with their own opacities would be the drift
    /// `tools_cohesion_verify.py` exists to catch.
    static var bevelSunk: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(highlight * 1.6), location: 0.0),
                .init(color: .white.opacity(highlight * 1.6), location: 0.5),
                .init(color: .black.opacity(shade * 1.4), location: 0.5),
                .init(color: .black.opacity(shade * 1.4), location: 1.0)
            ],
            startPoint: litFromTop ? .bottom : .top,
            endPoint: litFromTop ? .top : .bottom
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

    /// The full treatment: lit face, bevelled edge, and a cast shadow.
    ///
    /// This is what makes a drawn die and a rolled one read as the same
    /// object. The tray's camera is orthographic and top-down, so a die in
    /// play shows only its top face — the shading across it, the bevel at
    /// its edge and the shadow it throws are the entirety of what says it
    /// is solid, and a flat piece with none of them is a sticker.
    ///
    /// Takes an `InsettableShape` rather than a `Shape` because the bevel is
    /// drawn with `strokeBorder`, which only exists on the former — a plain
    /// `stroke` straddles the edge, so half the bevel would fall outside the
    /// die and the corner would read soft instead of turned.
    func pieceSolid<S: InsettableShape>(_ shape: S,
                                        elevation: Elevation = .piece,
                                        lineWidth: CGFloat = 2) -> some View {
        pieceSheen(shape)
            .overlay(shape.strokeBorder(PieceSheen.bevel, lineWidth: lineWidth))
            .elevated(elevation)
    }
}
