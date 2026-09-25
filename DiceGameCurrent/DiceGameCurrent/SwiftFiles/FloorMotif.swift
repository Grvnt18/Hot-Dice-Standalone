import UIKit

/// A shape carried by the floor's own facets, rather than painted over them.
///
/// Each game gets its own mark on the playing surface, and the point is that
/// it is made of the same triangles as everything around it: a facet whose
/// centre falls inside the motif is shaded a step lighter or darker, and the
/// shape emerges from the field. Drawing the mark on top would be a decal —
/// a different visual language sitting on the low-poly one.
///
/// Because the motif is only a tonal STEP, it works at every one of the
/// twenty-four table colours: the hue is whatever the player chose, and the
/// mark is the same colour a shade away. Nothing here is a fixed colour.
///
/// **The geometry is shared with `tools_motif_preview.py`**, which renders
/// each motif to a PNG. That preview exists because a "7" is either legible
/// in the triangles or it is not, and no amount of reading the numbers
/// settles which — the same reason the baseball field was previewed before
/// it was built. `tools_motif_verify.py` asserts the two agree, so what was
/// looked at is what draws.
enum FloorMotif: String {
    case none
    case seven          // Jackpot
    case pigFace        // HOG
    case stars          // Generals
    case circles        // Three Thousand
    case waves          // Freighter.Yacht.Dinghy
    case bones          // Boneheads
    case circuitry      // Rollbots
    case crowns         // Royal UR
    case diceShapes     // Free Roll

    /// One shape and the tonal step it applies.
    struct Shape {
        /// In normalised coordinates: 0...1 on both axes.
        let path: UIBezierPath
        /// Positive lightens the facet, negative darkens it.
        let lift: CGFloat
    }

    /// The standard step. Big enough to read from arm's length over a
    /// tumbling die, small enough that the floor still reads as one surface.
    static let lift: CGFloat = 0.30
    static let deep: CGFloat = -0.26

    /// Facets per side.
    ///
    /// The house floor is 16, too coarse to hold a numeral or a face — at
    /// that size a "7" is four triangles and a guess. A centred motif gets
    /// 30, so 1,800 triangles carry the shape.
    ///
    /// **A repeated motif needs more**, because each mark is a fraction of
    /// the size: the first tiled sevens were seven facets across and read
    /// as arrows. Generated once and cached, so the extra cost is paid on
    /// the first roll of a game and never again.
    var grid: Int? {
        switch self {
        case .none:                                   return nil
        case .seven, .crowns:                         return 52
        case .bones, .circuitry, .diceShapes:         return 44
        case .pigFace, .stars, .circles, .waves:      return 30
        }
    }

    // MARK: The shapes

    var shapes: [Shape] {
        switch self {
        case .none:
            return []

        case .seven:
            return tiled(columns: 2, rows: 3, inset: 0.14, cell: sevenGlyph)

        case .pigFace:
            // Built to read like icon-hog.png: big upright ears, a broad
            // head, two slit eyes, and a LIGHT snout carrying two dark
            // nostrils. The snout being lighter than the head rather than
            // darker is what stopped it reading as an open mouth.
            var out: [Shape] = []
            for side in [-1.0, 1.0] as [CGFloat] {
                out.append(Shape(path: polygon([(0.5 + side * 0.10, 0.42),
                                                (0.5 + side * 0.20, 0.09),
                                                (0.5 + side * 0.36, 0.26),
                                                (0.5 + side * 0.34, 0.46)]),
                                 lift: Self.lift))
            }
            out.append(Shape(path: ellipse(0.5, 0.56, 0.325, 0.295),
                             lift: Self.lift))
            for side in [-1.0, 1.0] as [CGFloat] {
                out.append(Shape(path: ellipse(0.5 + side * 0.145, 0.47,
                                               0.034, 0.056), lift: Self.deep))
            }
            out.append(Shape(path: ellipse(0.5, 0.68, 0.162, 0.115),
                             lift: Self.lift + 0.26))
            for side in [-1.0, 1.0] as [CGFloat] {
                out.append(Shape(path: ellipse(0.5 + side * 0.058, 0.68,
                                               0.027, 0.046), lift: Self.deep))
            }
            return out

        case .stars:
            return [(0.50, 0.46, 0.235), (0.17, 0.19, 0.105),
                    (0.83, 0.19, 0.105), (0.15, 0.78, 0.120),
                    (0.85, 0.78, 0.120), (0.50, 0.88, 0.090)]
                .map { Shape(path: star($0.0, $0.1, $0.2), lift: Self.lift) }

        case .circles:
            return [Shape(path: ring(0.5, 0.5, 0.46, 0.38), lift: Self.lift),
                    Shape(path: ring(0.5, 0.5, 0.31, 0.23), lift: Self.lift),
                    Shape(path: circle(0.5, 0.5, 0.15), lift: Self.lift)]

        case .waves:
            return [0.18, 0.42, 0.66, 0.90].map {
                Shape(path: wave(y: $0, amplitude: 0.052,
                                 cycles: 2, thickness: 0.075),
                      lift: Self.lift)
            }

        case .bones:
            return tiled(columns: 2, rows: 3, inset: 0.06, cell: boneTile)

        case .circuitry:
            return tiled(columns: 3, rows: 4, inset: 0.04, cell: circuitTile)

        case .crowns:
            return tiled(columns: 2, rows: 3, inset: 0.12, cell: crown)

        case .diceShapes:
            return tiled(columns: 3, rows: 4, inset: 0.0, cell: dieShape)
        }
    }

    // MARK: Tiling

    /// Stamps one shape across the floor on a staggered grid.
    ///
    /// Three motifs were a single mark in the middle with bare field
    /// around it. A rolling area is looked at as a whole, so a mark that
    /// occupies only its centre reads as an object dropped on the floor
    /// rather than as a surface.
    ///
    /// Odd rows are offset half a cell: a plain grid reads as wallpaper,
    /// and the stagger is what makes it read as a field.
    private func tiled(columns: Int, rows: Int, inset: CGFloat,
                       cell: (CGFloat, CGFloat, CGFloat) -> [Shape]) -> [Shape] {
        let cw = 1.0 / CGFloat(columns)
        let ch = 1.0 / CGFloat(rows)
        let size = min(cw, ch) * (1.0 - inset)
        var out: [Shape] = []
        for row in 0..<rows {
            for col in 0..<columns {
                let shift: CGFloat = row % 2 == 1 ? cw / 2 : 0.0
                let cx = (CGFloat(col) + 0.5) * cw + shift
                guard cx <= 1.0 + cw / 4 else { continue }
                out += cell(cx, (CGFloat(row) + 0.5) * ch, size)
            }
        }
        return out
    }

    /// A stable choice from a cell's position.
    ///
    /// No RNG: the floor must look the same every launch, and this gets
    /// that without threading a seed through every builder.
    private func pick(_ cx: CGFloat, _ cy: CGFloat, _ count: Int) -> Int {
        (Int(cx * 97) + Int(cy * 61)) % count
    }

    /// A numeral 7, sized and centred on a cell.
    private func sevenGlyph(_ cx: CGFloat, _ cy: CGFloat,
                            _ size: CGFloat) -> [Shape] {
        func place(_ points: [(CGFloat, CGFloat)]) -> [(CGFloat, CGFloat)] {
            points.map { (cx + ($0.0 - 0.5) * size, cy + ($0.1 - 0.5) * size) }
        }
        return [
            Shape(path: polygon(place([(0.26, 0.20), (0.76, 0.20), (0.76, 0.32),
                                       (0.55, 0.82), (0.40, 0.82), (0.60, 0.33),
                                       (0.26, 0.33)])), lift: Self.lift),
            // The European crossbar, which is not decoration: without it
            // the diagonal reads as a 1 at facet resolution.
            Shape(path: polygon(place([(0.38, 0.52), (0.64, 0.52),
                                       (0.62, 0.59), (0.36, 0.59)])),
                  lift: Self.lift)
        ]
    }

    /// Three points over a band, with a jewel on each point.
    private func crown(_ cx: CGFloat, _ cy: CGFloat,
                       _ size: CGFloat) -> [Shape] {
        let body: [(CGFloat, CGFloat)] = [
            (-0.42, 0.12), (-0.30, -0.34), (-0.14, 0.00), (0.0, -0.42),
            (0.14, 0.00), (0.30, -0.34), (0.42, 0.12), (0.34, 0.34),
            (-0.34, 0.34)
        ]
        var out = [Shape(path: polygon(body.map { (cx + $0.0 * size,
                                                   cy + $0.1 * size) }),
                         lift: Self.lift)]
        let jewels: [(CGFloat, CGFloat)] = [(-0.30, -0.36), (0.0, -0.44),
                                            (0.30, -0.36)]
        for jewel in jewels {
            out.append(Shape(path: circle(cx + jewel.0 * size,
                                          cy + jewel.1 * size, 0.075 * size),
                             lift: Self.lift))
        }
        // The band, a shade deeper so the crown is not one blob.
        out.append(Shape(path: polygon([(cx - 0.36 * size, cy + 0.16 * size),
                                        (cx + 0.36 * size, cy + 0.16 * size),
                                        (cx + 0.34 * size, cy + 0.30 * size),
                                        (cx - 0.34 * size, cy + 0.30 * size)]),
                         lift: Self.deep * 0.55))
        return out
    }

    /// Alternating d6 and d4 silhouettes — a square and a triangle.
    ///
    /// Two shapes rather than six: at this facet size a pentagon and a
    /// hexagon are the same blob and pips are a facet across, while a
    /// square beside a triangle is unmistakable.
    private func dieShape(_ cx: CGFloat, _ cy: CGFloat,
                          _ size: CGFloat) -> [Shape] {
        let r = size * 0.42
        if pick(cx, cy, 2) == 0 {
            return [Shape(path: polygon([(cx - r, cy - r), (cx + r, cy - r),
                                         (cx + r, cy + r), (cx - r, cy + r)]),
                          lift: Self.lift)]
        }
        let h = r * 1.15
        return [Shape(path: polygon([(cx, cy - h),
                                     (cx + h * 0.92, cy + h * 0.62),
                                     (cx - h * 0.92, cy + h * 0.62)]),
                      lift: Self.lift)]
    }

    private func boneTile(_ cx: CGFloat, _ cy: CGFloat,
                          _ size: CGFloat) -> [Shape] {
        let angle: CGFloat = pick(cx, cy, 2) == 1 ? 0.6 : -0.6
        return bone(cx: cx, cy: cy, length: size * 0.78,
                    thickness: size * 0.17, angle: angle)
    }

    /// An L of trace with a pad at its corner, turned by position.
    private func circuitTile(_ cx: CGFloat, _ cy: CGFloat,
                             _ size: CGFloat) -> [Shape] {
        let s = size * 0.5
        let turn = pick(cx, cy, 4)
        let dx: CGFloat = (turn == 0 || turn == 3) ? 1 : -1
        let dy: CGFloat = (turn == 0 || turn == 1) ? 1 : -1
        let w = size * 0.13
        return [
            Shape(path: trace(cx - dx * s, cy, cx, cy, w), lift: Self.lift),
            Shape(path: trace(cx, cy, cx, cy + dy * s, w), lift: Self.lift),
            Shape(path: circle(cx, cy, size * 0.15), lift: Self.lift),
            Shape(path: circle(cx - dx * s, cy, size * 0.10), lift: Self.lift)
        ]
    }

    // MARK: Builders

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> UIBezierPath {
        let path = UIBezierPath()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: point.0, y: point.1)
            index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.close()
        return path
    }

    /// A circle, spelled with one radius.
    ///
    /// Not just sugar: `tools_motif_verify.py` compares the two sources
    /// number for number, and a radius written twice on one side and once
    /// on the other reads as drift when it is nothing of the kind.
    private func circle(_ cx: CGFloat, _ cy: CGFloat,
                        _ r: CGFloat) -> UIBezierPath {
        ellipse(cx, cy, r, r)
    }

    private func ellipse(_ cx: CGFloat, _ cy: CGFloat,
                         _ rx: CGFloat, _ ry: CGFloat) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry,
                                    width: rx * 2, height: ry * 2))
    }

    /// Outer circle with the inner one knocked out.
    ///
    /// Even-odd rather than two separate shapes: `contains(_:)` respects the
    /// fill rule, so the hole is a hole for the facet test too.
    private func ring(_ cx: CGFloat, _ cy: CGFloat,
                      _ outer: CGFloat, _ inner: CGFloat) -> UIBezierPath {
        let path = circle(cx, cy, outer)
        path.append(circle(cx, cy, inner))
        path.usesEvenOddFillRule = true
        return path
    }

    private func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat,
                      points: Int = 5, inner: CGFloat = 0.40) -> UIBezierPath {
        let rotation = -CGFloat.pi / 2          // a point straight up
        var vertices: [(CGFloat, CGFloat)] = []
        for i in 0..<(points * 2) {
            let radius = i % 2 == 0 ? r : r * inner
            let angle = rotation + CGFloat(i) * .pi / CGFloat(points)
            vertices.append((cx + radius * cos(angle), cy + radius * sin(angle)))
        }
        return polygon(vertices)
    }

    /// A shaft with a pair of knobs at each end.
    private func bone(cx: CGFloat, cy: CGFloat, length: CGFloat,
                      thickness: CGFloat, angle: CGFloat) -> [Shape] {
        let ca = cos(angle), sa = sin(angle)
        func at(_ u: CGFloat, _ v: CGFloat) -> (CGFloat, CGFloat) {
            (cx + u * ca - v * sa, cy + u * sa + v * ca)
        }
        let half = length / 2
        let knob = thickness * 0.62
        var out = [Shape(path: polygon([at(-half, -thickness / 2),
                                        at(half, -thickness / 2),
                                        at(half, thickness / 2),
                                        at(-half, thickness / 2)]),
                         lift: Self.lift)]
        for end in [-half, half] {
            for side in [-1.0, 1.0] as [CGFloat] {
                let c = at(end, side * knob * 0.55)
                out.append(Shape(path: circle(c.0, c.1, knob),
                                 lift: Self.lift))
            }
        }
        return out
    }

    private func wave(y: CGFloat, amplitude: CGFloat,
                      cycles: CGFloat, thickness: CGFloat,
                      samples: Int = 48) -> UIBezierPath {
        var top: [(CGFloat, CGFloat)] = []
        var bottom: [(CGFloat, CGFloat)] = []
        for i in 0...samples {
            let x = CGFloat(i) / CGFloat(samples)
            let yy = y + amplitude * sin(2 * .pi * cycles * x)
            top.append((x, yy - thickness / 2))
            bottom.append((x, yy + thickness / 2))
        }
        return polygon(top + bottom.reversed())
    }

    /// An axis-aligned circuit trace.
    private func trace(_ x0: CGFloat, _ y0: CGFloat,
                       _ x1: CGFloat, _ y1: CGFloat,
                       _ w: CGFloat) -> UIBezierPath {
        if abs(y1 - y0) < 1e-9 {
            return polygon([(min(x0, x1), y0 - w / 2), (max(x0, x1), y0 - w / 2),
                            (max(x0, x1), y0 + w / 2), (min(x0, x1), y0 + w / 2)])
        }
        return polygon([(x0 - w / 2, min(y0, y1)), (x0 + w / 2, min(y0, y1)),
                        (x0 + w / 2, max(y0, y1)), (x0 - w / 2, max(y0, y1))])
    }
}
