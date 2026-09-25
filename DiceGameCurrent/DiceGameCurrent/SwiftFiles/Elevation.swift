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

    var opacity: Double {
        switch self {
        case .resting: return 0.28
        case .piece:   return 0.34
        case .lifted:  return 0.45
        }
    }

    /// How far the shadow spreads. Higher things throw softer edges.
    var radius: CGFloat {
        switch self {
        case .resting: return 2
        case .piece:   return 3
        case .lifted:  return 5
        }
    }

    /// How far the shadow is thrown along the light's direction.
    var offset: CGFloat {
        switch self {
        case .resting: return 1
        case .piece:   return 2
        case .lifted:  return 3
        }
    }

    /// Signed for the light: away from it, whichever way it points.
    var dy: CGFloat { PieceSheen.litFromTop ? offset : -offset }

    var color: Color { .black.opacity(opacity) }
}

extension View {
    /// Casts this view's shadow at a named height.
    ///
    /// The one way to put a shadow on anything in this app —
    /// `tools_cohesion_verify.py` fails a hand-written `.shadow(` so the
    /// four values cannot quietly become five.
    func elevated(_ elevation: Elevation) -> some View {
        shadow(color: elevation.color,
               radius: elevation.radius,
               y: elevation.dy)
    }
}
