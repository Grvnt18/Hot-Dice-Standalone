import SwiftUI
import UIKit

// MARK: - Materials

/// The board's palette and markings.
///
/// Built from what the app already uses rather than new art: the frame is
/// the same timber as the header and the Roll button, the tiles are the
/// same faceted low-poly surface as the playfield floor, and the ink and
/// petal red are lifted straight from the existing swatch lists — Midnight
/// Navy from `AppTheme.swatches` and the red body from `DiePalette`. The
/// markings themselves follow the traditional board: rosettes, eyes, the
/// five-dot quincunx, a dotted field, a grid of squares, and the
/// zigzag-and-five.
enum RoyalUrArt {

    static let ink = Color(hex: "#1B2A4A")
    static let petalRed = Color(hex: "#DB362C")
    static let tileBase = UIColor(hex: "#F4EDDF")

    /// The same generator the floor uses, at a much lower variation — a
    /// board tile should read as aged ivory, not as a patchwork.
    static let tileTexture = LowPolyTextures.facetedSurface(
        baseColor: tileBase,
        variation: 0.045,
        columns: 6,
        rows: 6,
        pixelSize: 256,
        seed: 8821
    )

    /// Seat 0 takes the red of the rosette petals, seat 1 the navy, so the
    /// pieces belong to the board rather than sitting on top of it.
    static func seatColor(_ seat: Int) -> Color {
        seat == RoyalUrBoard.bottomSeat ? petalRed : ink
    }
}

// MARK: - Layout

/// Where every square sits, for a given view size.
///
/// The board is 8 squares by 3 with a one-square-wide gap between them and
/// a margin of frame around the outside, so its natural aspect is a little
/// over 2.5:1. Everything is derived from one tile size, which keeps the
/// gaps and the frame in proportion at any scale.
struct RoyalUrLayout {

    let tile: CGFloat
    let gap: CGFloat
    let margin: CGFloat
    let boardSize: CGSize
    let origin: CGPoint

    init(size: CGSize) {
        // gap = 0.08 tile, margin = 0.18 tile, so:
        //   width  = 8 tiles + 7 gaps + 2 margins = 8.92 tiles
        //   height = 3 tiles + 2 gaps + 2 margins = 3.52 tiles
        let tile = max(min(size.width / 8.92, size.height / 3.52), 1)
        self.tile = tile
        self.gap = tile * 0.08
        self.margin = tile * 0.18
        self.boardSize = CGSize(width: tile * 8.92, height: tile * 3.52)
        self.origin = CGPoint(
            x: (size.width - tile * 8.92) / 2,
            y: (size.height - tile * 3.52) / 2
        )
    }

    func rect(for square: RoyalUrBoard.Square) -> CGRect {
        CGRect(
            x: origin.x + margin + CGFloat(square.column - 1) * (tile + gap),
            y: origin.y + margin + CGFloat(square.row - 1) * (tile + gap),
            width: tile,
            height: tile
        )
    }

    func center(of square: RoyalUrBoard.Square) -> CGPoint {
        let r = rect(for: square)
        return CGPoint(x: r.midX, y: r.midY)
    }
}

// MARK: - Board

/// The board itself: frame, twenty marked squares, and whatever pieces are
/// standing on them.
struct RoyalUrBoardView: View {

    /// Where each seat's pieces are, as path indices: 0 is waiting to
    /// enter, 1...16 is on the board, 17 is home.
    var positions: [[Int]] = [[0, 0, 0], [0, 0, 0]]

    /// Squares to ring in the accent colour — what you may tap.
    var highlighted: Set<RoyalUrBoard.Square> = []

    /// The piece currently chosen, drawn with a ring of its own so you
    /// can see which one is about to move.
    var focused: RoyalUrBoard.Square? = nil

    /// Where the chosen piece would land. Drawn heavier than a mere
    /// highlight, because this is the one square that commits the move.
    var destination: RoyalUrBoard.Square? = nil

    var onTapSquare: ((RoyalUrBoard.Square) -> Void)? = nil

    @ObservedObject private var theme = AppTheme.shared

    var body: some View {
        GeometryReader { geo in
            let layout = RoyalUrLayout(size: geo.size)

            ZStack {
                // The frame is the app's own timber, pushed darker so it
                // reads as a board edge rather than as more of the header.
                //
                // It fills the WHOLE frame rather than just the board's
                // own 2.53:1. The plate used to be `layout.boardSize`, so
                // whenever the frame did not share that ratio the table
                // colour showed through beside it — two coloured bars
                // down the sides on a tablet, where the layout is
                // height-bound, and a strip above and below on a phone.
                // Timber edge to edge cannot leave one at any size, and
                // the squares stay exactly where RoyalUrLayout puts them.
                WoodTiledBackground()
                    .overlay(Color.black.opacity(0.22))
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: layout.tile * 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: layout.tile * 0.14)
                            .stroke(Color.black.opacity(0.45), lineWidth: 2)
                            .frame(width: geo.size.width, height: geo.size.height)
                    )
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                Canvas { context, _ in
                    draw(in: context, layout: layout)
                }

                if onTapSquare != nil {
                    tapTargets(layout)
                }
            }
        }
    }

    // MARK: Drawing

    private func draw(in context: GraphicsContext, layout: RoyalUrLayout) {
        let texture = context.resolve(Image(uiImage: RoyalUrArt.tileTexture))

        for square in RoyalUrBoard.squares {
            let rect = layout.rect(for: square)
            let shape = Path(roundedRect: rect, cornerRadius: layout.tile * 0.08)

            // The texture is drawn clipped rather than as a fill pattern,
            // which a GraphicsContext cannot do directly — a copy of the
            // context carries the clip so it does not leak to the rest of
            // the board.
            var tile = context
            tile.clip(to: shape)
            tile.draw(texture, in: rect)

            context.stroke(shape, with: .color(RoyalUrArt.ink.opacity(0.75)), lineWidth: 1.5)

            let inset = rect.insetBy(dx: layout.tile * 0.09, dy: layout.tile * 0.09)
            RoyalUrArt.draw(
                RoyalUrBoard.decor(at: square),
                in: context,
                rect: inset
            )

            if highlighted.contains(square) {
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: layout.tile * 0.1),
                    with: .color(theme.accentColor),
                    lineWidth: 3
                )
            }
        }

        // The off-board trays, drawn as outlines rather than tiles so they
        // read as somewhere pieces rest rather than somewhere they land.
        for seat in [0, 1] {
            tray(RoyalUrBoard.waitingTray(seat: seat), in: context, layout: layout, seat: seat)
            tray(RoyalUrBoard.homeTray(seat: seat), in: context, layout: layout, seat: seat)
        }

        // Pieces last, so they sit above the markings. Routed through
        // displaySquare, so a waiting or finished piece lands in its tray
        // instead of being skipped — which is what used to make them
        // disappear off the board entirely.
        for seat in positions.indices {
            var stackCount: [RoyalUrBoard.Square: Int] = [:]
            for index in positions[seat] {
                guard let square = RoyalUrBoard.displaySquare(seat: seat, index: index) else { continue }
                let slot = stackCount[square] ?? 0
                stackCount[square] = slot + 1

                let isTray = RoyalUrBoard.trayCells.contains(square)
                let radius = layout.tile * (isTray ? 0.17 : 0.30)
                var center = layout.center(of: square)
                if isTray {
                    // Three across, so three waiting pieces read as three.
                    center.x += (CGFloat(slot) - 1) * layout.tile * 0.30
                }

                RoyalUrArt.drawPiece(
                    in: context,
                    center: center,
                    radius: radius,
                    seat: seat
                )
            }
        }

        // The chosen piece and its landing square, over everything.
        if let focused {
            context.stroke(
                Path(roundedRect: layout.rect(for: focused).insetBy(dx: -3, dy: -3),
                     cornerRadius: layout.tile * 0.1),
                with: .color(.white.opacity(0.95)),
                lineWidth: 3
            )
        }
        if let destination {
            let rect = layout.rect(for: destination)
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: layout.tile * 0.1),
                with: .color(theme.accentColor),
                lineWidth: 5
            )
        }
    }

    /// An empty outline where a seat's pieces wait or rest.
    private func tray(
        _ square: RoyalUrBoard.Square,
        in context: GraphicsContext,
        layout: RoyalUrLayout,
        seat: Int
    ) {
        let rect = layout.rect(for: square).insetBy(dx: layout.tile * 0.10, dy: layout.tile * 0.10)
        let shape = Path(roundedRect: rect, cornerRadius: layout.tile * 0.08)
        context.fill(shape, with: .color(.black.opacity(0.22)))
        context.stroke(shape, with: .color(RoyalUrArt.seatColor(seat).opacity(0.5)), lineWidth: 1.5)
    }

    /// Invisible buttons over each square.
    ///
    /// Plain buttons rather than a tap gesture on the canvas: the canvas
    /// reports a point and would need the hit test done by hand, and this
    /// gets the tap target, the press feedback and the accessibility
    /// affordance for free.
    private func tapTargets(_ layout: RoyalUrLayout) -> some View {
        ForEach(RoyalUrBoard.squares + RoyalUrBoard.trayCells, id: \.self) { square in
            let rect = layout.rect(for: square)
            Button {
                onTapSquare?(square)
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
    }
}

// MARK: - Markings

extension RoyalUrArt {

    static func draw(_ decor: RoyalUrBoard.Decor, in context: GraphicsContext, rect: CGRect) {
        switch decor {
        case .rosette:     rosette(context, rect)
        case .eyes:        eyes(context, rect)
        case .fiveDots:    fiveDots(context, rect)
        case .dottedField: dottedField(context, rect)
        case .squaresGrid: squaresGrid(context, rect)
        case .zigzagFive:  zigzagFive(context, rect)
        }
    }

    /// A ringed dot — the motif nearly every marking is built from.
    private static func dot(_ context: GraphicsContext, _ center: CGPoint, _ radius: CGFloat) {
        let outer = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )
        context.stroke(Path(ellipseIn: outer), with: .color(ink), lineWidth: max(1, radius * 0.24))
        context.fill(Path(ellipseIn: outer.insetBy(dx: radius * 0.52, dy: radius * 0.52)), with: .color(ink))
    }

    private static func point(_ rect: CGRect, _ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * fx, y: rect.minY + rect.height * fy)
    }

    /// A line that zigzags between two points — the board's border motif.
    private static func zigzag(
        from start: CGPoint,
        to end: CGPoint,
        teeth: Int,
        amplitude: CGFloat
    ) -> Path {
        var path = Path()
        path.move(to: start)
        let dx = (end.x - start.x) / CGFloat(teeth)
        let dy = (end.y - start.y) / CGFloat(teeth)
        // Perpendicular to the run, so the same helper works on all four
        // edges and on the diagonals.
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        let nx = -dy / length * amplitude
        let ny = dx / length * amplitude
        for step in 1...teeth {
            let x = start.x + dx * CGFloat(step)
            let y = start.y + dy * CGFloat(step)
            let sign: CGFloat = step % 2 == 0 ? 1 : -1
            path.addLine(to: CGPoint(x: x - dx / 2 + nx * sign, y: y - dy / 2 + ny * sign))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }

    private static func zigzagBorder(_ context: GraphicsContext, _ rect: CGRect, teeth: Int) {
        let amplitude = rect.width * 0.05
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        for i in 0..<4 {
            context.stroke(
                zigzag(from: corners[i], to: corners[(i + 1) % 4], teeth: teeth, amplitude: amplitude),
                with: .color(ink.opacity(0.85)),
                lineWidth: max(1, rect.width * 0.022)
            )
        }
    }

    // MARK: The six markings

    /// Eight petals alternating red and navy inside a star outline — the
    /// rosette, and the only marking the rules care about.
    private static func rosette(_ context: GraphicsContext, _ rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = rect.width * 0.50
        let inner = outer * 0.46

        var star = Path()
        for i in 0..<16 {
            let angle = Double(i) * .pi / 8 - .pi / 2
            let radius = i % 2 == 0 ? outer : inner
            let p = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 { star.move(to: p) } else { star.addLine(to: p) }
        }
        star.closeSubpath()
        context.fill(star, with: .color(.white.opacity(0.9)))
        context.stroke(star, with: .color(ink), lineWidth: max(1, rect.width * 0.03))

        for i in 0..<8 {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let spread = Double.pi / 8
            var petal = Path()
            petal.move(to: center)
            petal.addLine(to: CGPoint(
                x: center.x + CGFloat(cos(angle - spread)) * inner,
                y: center.y + CGFloat(sin(angle - spread)) * inner
            ))
            petal.addLine(to: CGPoint(
                x: center.x + CGFloat(cos(angle)) * outer * 0.92,
                y: center.y + CGFloat(sin(angle)) * outer * 0.92
            ))
            petal.addLine(to: CGPoint(
                x: center.x + CGFloat(cos(angle + spread)) * inner,
                y: center.y + CGFloat(sin(angle + spread)) * inner
            ))
            petal.closeSubpath()
            context.fill(petal, with: .color(i % 2 == 0 ? petalRed : ink))
        }

        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - rect.width * 0.06, y: center.y - rect.width * 0.06,
                width: rect.width * 0.12, height: rect.width * 0.12
            )),
            with: .color(.white.opacity(0.9))
        )
    }

    /// Four lens shapes with a dot in each, and the vertical banding
    /// between them.
    private static func eyes(_ context: GraphicsContext, _ rect: CGRect) {
        let line = max(1, rect.width * 0.022)
        for fx in [0.26, 0.74] as [CGFloat] {
            for fy in [0.28, 0.72] as [CGFloat] {
                let center = point(rect, fx, fy)
                let halfHeight = rect.height * 0.19
                let bulge = rect.width * 0.14
                var lens = Path()
                lens.move(to: CGPoint(x: center.x, y: center.y - halfHeight))
                lens.addQuadCurve(
                    to: CGPoint(x: center.x, y: center.y + halfHeight),
                    control: CGPoint(x: center.x + bulge, y: center.y)
                )
                lens.addQuadCurve(
                    to: CGPoint(x: center.x, y: center.y - halfHeight),
                    control: CGPoint(x: center.x - bulge, y: center.y)
                )
                context.stroke(lens, with: .color(ink), lineWidth: line)
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - rect.width * 0.045, y: center.y - rect.width * 0.045,
                        width: rect.width * 0.09, height: rect.width * 0.09
                    )),
                    with: .color(ink)
                )
            }
        }
        for fx in [0.45, 0.55] as [CGFloat] {
            var bar = Path()
            bar.move(to: point(rect, fx, 0.06))
            bar.addLine(to: point(rect, fx, 0.94))
            context.stroke(bar, with: .color(ink.opacity(0.75)), lineWidth: line)
        }
    }

    /// The quincunx: four dots and a fifth in the middle.
    private static func fiveDots(_ context: GraphicsContext, _ rect: CGRect) {
        let radius = rect.width * 0.125
        for (fx, fy) in [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)] {
            dot(context, point(rect, CGFloat(fx), CGFloat(fy)), radius)
        }
    }

    /// A field of small dots inside a zigzag border.
    private static func dottedField(_ context: GraphicsContext, _ rect: CGRect) {
        zigzagBorder(context, rect, teeth: 5)
        let inner = rect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.16)
        let radius = rect.width * 0.032
        for row in 0..<4 {
            for column in 0..<4 {
                let center = CGPoint(
                    x: inner.minX + inner.width * (CGFloat(column) + 0.5) / 4,
                    y: inner.minY + inner.height * (CGFloat(row) + 0.5) / 4
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - radius, y: center.y - radius,
                        width: radius * 2, height: radius * 2
                    )),
                    with: .color(ink)
                )
            }
        }
    }

    /// Nine little squares, each with a dot.
    private static func squaresGrid(_ context: GraphicsContext, _ rect: CGRect) {
        let line = max(1, rect.width * 0.018)
        let cell = rect.width / 3
        for row in 0..<3 {
            for column in 0..<3 {
                let box = CGRect(
                    x: rect.minX + CGFloat(column) * cell,
                    y: rect.minY + CGFloat(row) * cell,
                    width: cell, height: cell
                ).insetBy(dx: cell * 0.16, dy: cell * 0.16)
                context.stroke(Path(box), with: .color(ink.opacity(0.8)), lineWidth: line)
                let radius = cell * 0.13
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: box.midX - radius, y: box.midY - radius,
                        width: radius * 2, height: radius * 2
                    )),
                    with: .color(ink)
                )
            }
        }
    }

    /// A zigzag cross with five dots — the marking on the two far corners.
    private static func zigzagFive(_ context: GraphicsContext, _ rect: CGRect) {
        let amplitude = rect.width * 0.06
        let line = max(1, rect.width * 0.022)
        context.stroke(
            zigzag(
                from: CGPoint(x: rect.minX, y: rect.minY),
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                teeth: 4, amplitude: amplitude
            ),
            with: .color(ink.opacity(0.85)), lineWidth: line
        )
        context.stroke(
            zigzag(
                from: CGPoint(x: rect.maxX, y: rect.minY),
                to: CGPoint(x: rect.minX, y: rect.maxY),
                teeth: 4, amplitude: amplitude
            ),
            with: .color(ink.opacity(0.85)), lineWidth: line
        )
        let radius = rect.width * 0.075
        for (fx, fy) in [(0.5, 0.16), (0.16, 0.5), (0.5, 0.5), (0.84, 0.5), (0.5, 0.84)] {
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point(rect, CGFloat(fx), CGFloat(fy)).x - radius,
                    y: point(rect, CGFloat(fx), CGFloat(fy)).y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(ink)
            )
        }
    }

    // MARK: Pieces

    static func drawPiece(
        in context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        seat: Int
    ) {
        let body = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )
        // Cast, not concentric. This was a slightly larger ellipse centred
        // on the piece, which is a glow — a shadow falls AWAY from the
        // light, and Elevation is where that direction and depth are
        // stated for the whole app.
        context.fill(Path(ellipseIn: body.offsetBy(dx: 0, dy: Elevation.piece.dy)),
                     with: .color(Elevation.piece.color))
        context.fill(Path(ellipseIn: body), with: .color(seatColor(seat)))
        // The same sheen the placed dice carry, so a piece on this board
        // and a die on the tray read as the same material. See PieceSheen.
        context.fill(Path(ellipseIn: body), with: PieceSheen.shading(in: body))
        context.stroke(Path(ellipseIn: body), with: .color(.white.opacity(0.9)),
                       lineWidth: max(1, radius * 0.16))
        context.stroke(Path(ellipseIn: body.insetBy(dx: radius * 0.34, dy: radius * 0.34)),
                       with: .color(.white.opacity(0.65)), lineWidth: max(1, radius * 0.12))
    }
}
