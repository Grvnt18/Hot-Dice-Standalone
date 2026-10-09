import SwiftUI

/// How far above its surface a thing sits, and the shadow that says so.
///
/// There were four hand-picked shadows in the app and nothing said what
/// any of them meant: `0.5 / radius 4 / y 2` under the hub wordmark, 0.22
/// under Royal UR's trays, 0.25 under its pieces, 0.22 over the board.
/// Four values, four opinions, no rule — which is how a suite stops
/// reading as one object without anyone being able to point at why.
///
/// Three heights, because three is what the app actually has: something
/// lying on the table, something resting on a board, and something picked
/// up. Anything that needs a fourth should get a name here rather than a
/// number at the call site.
///
/// **The direction comes from `PieceSheen.litFromTop`**, so the shadow
/// falls away from the same light the highlight comes from. Those two were
/// set independently before, and a piece lit from above with its shadow
/// cast upward is exactly the sort of thing that reads as wrong without
/// being nameable.
enum Elevation {

    case resting     // a sheet of paper on the table
    case piece       // a die or a counter on a board
    case lifted      // the hub's wordmark, a card held out

    /// Raised across the board, because a hard-edged shadow at the old
    /// opacities reads as a smudge rather than as a silhouette. With no blur
    /// to soften it, the shadow either commits or looks like a mistake.
    /// A quarter lighter than it was: 0.45/0.55/0.70 became 0.34/0.41/0.53.
    /// The ladder keeps its proportions — three heights that stop being a
    /// sequence stop being three heights, same reason `offset` was doubled
    /// in proportion rather than only where the hub needed it.
    var opacity: Double {
        switch self {
        case .resting: return 0.34
        case .piece:   return 0.41
        case .lifted:  return 0.53
        }
    }

    /// How far the shadow spreads — which is now nowhere, at every height.
    ///
    /// A blurred shadow is the single thing that most stops a UI reading as
    /// pixel art. Everything else can be flat, hard-edged and four-tone, and
    /// one soft grey halo under a button still says "rendered". So the three
    /// heights are now told apart by how FAR the shadow is thrown rather than
    /// how soft it is, which is what a sprite does: a hard offset silhouette,
    /// one, two or three whole pixels clear of the thing casting it.
    var radius: CGFloat { 0 }

    /// How far the shadow is thrown along the light's direction.
    ///
    /// Whole pixels, and now the ONLY thing separating the three heights —
    /// see `radius`. Also thrown sideways as well as down, because a hard
    /// shadow directly below reads as a seam rather than as a shadow.
    ///
    /// Doubled from 1/2/3, because at those distances it read as noise
    /// rather than as depth. A 3pt offset under a 95pt hub icon is three
    /// percent — near enough to the sprite's own edge to look like a
    /// rasterising artefact, which is precisely what was reported. The
    /// ladder is kept in proportion rather than raising only the height the
    /// hub happens to use: three heights that are no longer a sequence stop
    /// being three heights.
    var offset: CGFloat {
        switch self {
        case .resting: return 2
        case .piece:   return 4
        case .lifted:  return 6
        }
    }

    /// Sideways throw. Half the vertical, rounded to a whole pixel, so the
    /// light stays up-and-slightly-left the way PieceSheen assumes.
    var dx: CGFloat { (offset / 2).rounded() }

    /// Signed for the light: away from it, whichever way it points.
    var dy: CGFloat { PieceSheen.litFromTop ? offset : -offset }

    /// Which way the shadow is signed in TONE, the way `dy` signs it in
    /// direction.
    ///
    /// A dark mark on mid-tone timber cannot throw a dark shadow. The hub's
    /// wordmark is black on wood now, and a black offset behind black
    /// glyphs is not depth — it is a thickened edge, which is the other
    /// half of the "reads as noise" report. So the hub throws a pale
    /// shadow instead, off the same distances and the same opacities.
    ///
    /// Two tones, one ladder: both are the shared `opacity` against a
    /// different base, which is the whole reason this is still one shadow
    /// system rather than two. `tools_cohesion_verify.py` checks that,
    /// because an ink with numbers of its own is how it would stop being
    /// true.
    enum Ink {
        case dark      // anything on a light or mid surface
        case light     // a dark mark on a mid surface — the hub
    }

    func color(_ ink: Ink) -> Color {
        switch ink {
        case .dark:  return .black.opacity(opacity)
        case .light: return .white.opacity(opacity)
        }
    }
}

extension View {
    /// Casts this view's shadow at a named height.
    ///
    /// The one way to put a shadow on anything in this app —
    /// `tools_cohesion_verify.py` fails a hand-written `.shadow(` so the
    /// four values cannot quietly become five.
    ///
    /// `ink` defaults to `.dark`, so every call site that predates the
    /// second tone keeps exactly the shadow it had.
    func elevated(_ elevation: Elevation,
                  ink: Elevation.Ink = .dark) -> some View {
        shadow(color: elevation.color(ink),
               radius: elevation.radius,
               x: elevation.dx,
               y: elevation.dy)
    }
}
