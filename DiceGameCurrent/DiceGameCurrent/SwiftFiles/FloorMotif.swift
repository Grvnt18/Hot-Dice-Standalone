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
    /// The house floor is 16, which is too coarse to hold a numeral or a
    /// face — at that size a "7" is four triangles and a guess. A motif
    /// floor is 30, so 1,800 triangles carry the shape. Generated once and
    /// cached, so the extra cost is paid on the first roll of a game and
    /// never again.
    var grid: Int? { self == .none ? nil : 30 }

    // MARK: The shapes

    var shapes: [Shape] {
        switch self {
        case .none:
            return []

        case .seven:
            // One closed numeral, plus the European crossbar — which is
            // not decoration: without it the diagonal reads as a 1 at
            // facet resolution.
            return [
                Shape(path: polygon([(0.26, 0.20), (0.76, 0.20), (0.76, 0.32),
                                     (0.55, 0.82), (0.40, 0.82), (0.60, 0.33),
                                     (0.26, 0.33)]), lift: Self.lift),
                Shape(path: polygon([(0.38, 0.52), (0.64, 0.52),
                                     (0.62, 0.59), (0.36, 0.59)]),
                      lift: Self.lift)
            ]

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
            return [(0.30, 0.26, 0.34, 0.075, 0.5),
                    (0.72, 0.34, 0.30, 0.068, -0.7),
                    (0.26, 0.70, 0.30, 0.068, -0.45),
                    (0.68, 0.76, 0.34, 0.075, 0.6)]
                .flatMap { bone(cx: $0.0, cy: $0.1, length: $0.2,
                                thickness: $0.3, angle: $0.4) }

        case .circuitry:
            let width: CGFloat = 0.040
            var out = [(0.12, 0.22, 0.62, 0.22), (0.62, 0.22, 0.62, 0.50),
                       (0.62, 0.50, 0.88, 0.50), (0.24, 0.22, 0.24, 0.74),
                       (0.24, 0.74, 0.54, 0.74), (0.54, 0.74, 0.54, 0.90),
                       (0.40, 0.38, 0.88, 0.38), (0.76, 0.62, 0.76, 0.90),
                       (0.12, 0.54, 0.40, 0.54), (0.40, 0.54, 0.40, 0.38)]
                .map { Shape(path: trace($0.0, $0.1, $0.2, $0.3, width),
                             lift: Self.lift) }
            out += [(0.62, 0.22), (0.62, 0.50), (0.24, 0.74), (0.54, 0.74),
                    (0.40, 0.38), (0.40, 0.54), (0.76, 0.62), (0.88, 0.50)]
                .map { Shape(path: circle($0.0, $0.1, 0.048),
                             lift: Self.lift) }
            return out
        }
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
