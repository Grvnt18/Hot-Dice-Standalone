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
// The chrome panel and the shared back/settings button live here rather
// than in a PixelPanel.swift of their own. Swift Playgrounds does not
// pick up a new file by itself, so every stage of this rollout stays
// REPLACEMENTS ONLY — a stage that fails is then broken code, never a
// file somebody forgot to add.
//
// TAKEN FROM 82abaf2, the LAST commit in the restyle that touches this
// code — not from ed57f86, where the merge conflict surfaced. That
// distinction cost three compile errors: a later commit modified a file
// git had already staged as deleted, so its hunk was dropped with no
// conflict and no warning. When re-folding, take the final version, not
// the one that conflicted.
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
    ///
    /// That is what this comment always said, and for a while only the
    /// corner was implemented: the outline stayed at 2pt, so on a 375pt
    /// phone a ~30pt cell spent 8 of those 30 points on outline and bevel —
    /// a quarter of it — and the quarter it spent was exactly the die's own
    /// body colour, which is the thing the cells exist to show.
    static let cellRadius: CGFloat = 2
    static let cellOutline: CGFloat = 1
    static let cellBevel: CGFloat = 1

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

    /// One border around the whole playing area.
    ///
    /// The same edge the settings button wears — a near-black outline with
    /// a lit bevel inset inside it — and deliberately NO shadow: this is a
    /// frame around the thing, not an object sitting on top of something
    /// else.
    ///
    /// Applied once, where the hub presents a game, rather than on each of
    /// the eleven screens. It therefore traces the SAFE AREA rather than
    /// the glass: a screen's backgrounds call `.ignoresSafeArea()` and
    /// bleed past it, but the screen's own layout bounds stop there, and a
    /// border under the home indicator is a border nobody sees.
    func gameFrame(radius: CGFloat = ControlShape.cornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .overlay(
                shape.inset(by: PixelPanel.outlineWidth)
                    .strokeBorder(PieceSheen.bevel,
                                  lineWidth: PixelPanel.bevelWidth)
            )
            .overlay(
                shape.strokeBorder(PixelPanel.outlineColor,
                                   lineWidth: PixelPanel.outlineWidth)
            )
    }

    /// Frames this view as a pixel panel.
    ///
    /// The one way to put a chrome edge on anything, the way `.elevated(_:)`
    /// is the one way to put a shadow on it.
    func pixelPanel(fill: PixelPanel.Fill = .none,
                    elevation: Elevation = .resting,
                    radius: CGFloat = ControlShape.cornerRadius,
                    outline: CGFloat = PixelPanel.outlineWidth,
                    bevel: CGFloat = PixelPanel.bevelWidth) -> some View {
        modifier(PixelPanel(fill: fill, elevation: elevation, radius: radius,
                            outline: outline, bevel: bevel))
    }

    /// A panel sunk INTO its surface rather than sitting on it — an empty
    /// score cell, a slot waiting to be filled.
    ///
    /// The same parts with the light reversed: the bevel runs dark-over-light
    /// instead of light-over-dark, and there is no shadow, because nothing
    /// below the surface throws one.
    func pixelWell(radius: CGFloat = ControlShape.cornerRadius,
                   outline: CGFloat = PixelPanel.outlineWidth,
                   bevel: CGFloat = PixelPanel.bevelWidth) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .overlay(shape.inset(by: outline)
                .strokeBorder(PieceSheen.bevel, lineWidth: bevel)
                .rotationEffect(.degrees(180)))
            .overlay(shape.strokeBorder(PixelPanel.outlineColor.opacity(0.55),
                                        lineWidth: outline))
            .clipShape(shape)
    }
}

// MARK: - Overlay chrome button

/// The small round-cornered button that sits over a playfield: back, and
/// settings.
///
/// Three screens each carried their own copy of this — Royal UR, Rollbots
/// and Baseball Dice — identical but for the ink colour and one of them
/// having forgotten the chevron's heavier weight. Three copies of a thing
/// that must look the same is how a suite drifts apart, and the restyle is
/// exactly when it shows: a panel treatment applied to two of three reads
/// as a bug rather than as a variant.
///
/// The scrim stays a black wash rather than becoming a `.solid` fill: these
/// sit over a live scene, and a button that hides what is behind it in a
/// corner of the tray is worse than one you can partly see through.
struct OverlayChromeButton: View {
    let systemName: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18,
                              weight: systemName == "chevron.left" ? .semibold : .regular))
                .foregroundStyle(tint.opacity(0.85))
                .padding(9)
                .background(Color.black.opacity(0.5))
                .pixelPanel(radius: PixelPanel.cellRadius)
        }
        .padding(10)
    }
}

// MARK: - Die-shaped slots

/// The outline a banking slot wears, by the kind of die it holds.
///
/// Rolls' pool is twelve d6 and one each of d8, d10 and d12, and the history
/// grid used to draw fifteen identical rounded cells — so the three dice
/// that are not d6 were invisible until you read their numbers. The last
/// three slots are now reserved for them and cut to the shape of their own
/// face: a triangle for the d8, a diamond for the d10, a pentagon for the
/// d12.
///
/// Flat geometry, no curves beyond the square's existing corner: these are
/// drawn at about 30pt and a rounded polygon at that size is mush.
enum DieSlotShape: Equatable {
    case square
    case triangle
    case diamond
    case pentagon

    /// Which shape a die of this many sides lands in.
    static func forSides(_ sides: Int) -> DieSlotShape {
        switch sides {
        case 8:  return .triangle
        case 10: return .diamond
        case 12: return .pentagon
        default: return .square
        }
    }
}

/// `DieSlotShape` as something SwiftUI can fill and stroke.
struct DieSlot: InsettableShape {
    let kind: DieSlotShape

    /// How far in from the given rect to draw.
    ///
    /// `InsettableShape` rather than `Shape`, because a slot has to take
    /// the same three-layer edge every other panel wears — fill, a lit
    /// bevel inset inside the outline, then the outline — and both
    /// `strokeBorder` and `inset(by:)` need this conformance.
    /// `tools_cohesion_verify.py` fails a `strokeBorder` on a bare Shape
    /// precisely so this is not worked around with a plain `stroke`, which
    /// straddles the edge instead of sitting inside it.
    ///
    /// Shrinking the rect is the right inset for every shape here. For the
    /// square it is exactly what `insetBy` means; for the three polygons it
    /// is not a true mitred offset, but these are 1pt insets on a ~30pt
    /// slot and the difference is below a device pixel.
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> DieSlot {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in outer: CGRect) -> Path {
        let rect = outer.insetBy(dx: inset, dy: inset)
        return slotPath(in: rect)
    }

    private func slotPath(in rect: CGRect) -> Path {
        switch kind {
        case .square:
            return Path(roundedRect: rect, cornerRadius: PixelPanel.cellRadius)
        case .triangle:
            return polygon(in: rect, sides: 3)
        case .diamond:
            return polygon(in: rect, sides: 4)
        case .pentagon:
            return polygon(in: rect, sides: 5)
        }
    }

    /// A polygon with a point at the top, filling `rect` exactly.
    ///
    /// Out of the switch above and written as a loop for the usual reason:
    /// the vertices are trigonometry over an Int index, which is the shape
    /// of expression Xcode 14.2's solver gives up on inside a ViewBuilder.
    ///
    /// **Stretched to the box, not inscribed in a circle.** It used to put
    /// the vertices on a circle of `min(width, height) / 2`, which is a
    /// regular polygon — and a regular polygon does not fill a square.
    /// Measured on the unit circle, the triangle's own bounds came to 87%
    /// of the slot's width by 75% of its height and the pentagon's to 95%
    /// by 90%, so three of Rolls' banking slots read as visibly smaller
    /// spaces than the twelve squares beside them. These are the same slot
    /// in a different outline, so they take the same footprint.
    ///
    /// The ink follows: the triangle now covers 50% of its box where it
    /// covered 32%, and the pentagon 69% where it covered 59%.
    ///
    /// Filling a square means scaling the two axes by different amounts, so
    /// these are not quite regular — the triangle is a third taller than an
    /// equilateral one. That is the trade, and it is the right way round: a
    /// row of slots that are not the same size is the error a player sees.
    ///
    /// The diamond is the one that comes out exactly regular anyway, since
    /// its four vertices already sit on the box's edge midpoints.
    private func polygon(in rect: CGRect, sides: Int) -> Path {
        var points: [CGPoint] = []
        for index in 0..<sides {
            let turn = (Double(index) / Double(sides)) * 2 * Double.pi
            let angle = turn - Double.pi / 2
            points.append(CGPoint(x: CGFloat(cos(angle)),
                                  y: CGFloat(sin(angle))))
        }

        // The unit polygon's own bounds, which is what gets mapped onto the
        // rect. Computed rather than tabulated so adding a sixth side needs
        // nothing here.
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let minX = xs.min() ?? -1
        let minY = ys.min() ?? -1
        let spanX = (xs.max() ?? 1) - minX
        let spanY = (ys.max() ?? 1) - minY
        guard spanX > 0, spanY > 0 else { return Path(rect) }

        var path = Path()
        for (index, point) in points.enumerated() {
            let mapped = CGPoint(
                x: rect.minX + (point.x - minX) / spanX * rect.width,
                y: rect.minY + (point.y - minY) / spanY * rect.height)
            if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Menus and sheets

/// Sets the presented sheet's corner radius.
///
/// Every control in this app is cut square or very nearly so —
/// `ControlShape.cornerRadius` is 4 — and the one shape that ignored that
/// was the biggest one on screen: the card the Settings sheet is presented
/// in, which arrives with UIKit's own generous rounding.
///
/// It has to be done through UIKit. SwiftUI gained
/// `.presentationCornerRadius` in iOS 17 and this app's floor is iOS 16,
/// so the only way in is `UISheetPresentationController.preferredCornerRadius`
/// (iOS 15+), reached by walking the responder chain from a zero-sized view
/// planted in the sheet's own hierarchy.
///
/// Fails quietly and on purpose. A presentation that is not a sheet — a
/// popover on a wide iPad, a full-screen cover — has no
/// `sheetPresentationController`, and the right behaviour there is to leave
/// the system's shape alone rather than to force one.
struct SheetCorners: UIViewRepresentable {
    let radius: CGFloat

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ view: UIView, context: Context) {
        // Deferred by one runloop turn: on the first `updateUIView` the
        // view is not yet in the window, so the responder chain has no
        // controller on it and the radius would silently not apply.
        let wanted = radius
        DispatchQueue.main.async { [weak view] in
            guard let sheet = view?.owningController?.sheetPresentationController
            else { return }
            sheet.preferredCornerRadius = wanted
        }
    }
}

extension UIView {
    /// The nearest controller up the responder chain.
    var owningController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let controller = next as? UIViewController { return controller }
            responder = next
        }
        return nil
    }
}

extension View {
    /// The app's own sheet: squared corners and the same border the games
    /// wear.
    ///
    /// One modifier because it is one look. Settings had the two halves
    /// applied by hand and the two guide screens had neither, which is
    /// exactly how a "sheet style" ends up meaning three different things.
    func menuSheet() -> some View {
        self
            .background(SheetCorners(radius: ControlShape.cornerRadius))
            .gameFrame()
    }
}
