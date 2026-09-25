import UIKit

/// Procedurally generated faceted textures for the low-poly visual style.
///
/// These draw triangles into an image rather than building faceted
/// geometry. That's a deliberate shortcut and it's lossless here: the
/// floor has to stay geometrically flat so the visual surface matches the
/// physics collider (a bumpy visual floor would make dice appear to sink
/// or hover), so real facets could only differ in COLOR anyway — which is
/// exactly what a texture provides. One plane and one texture replaces
/// what would otherwise be hundreds of geometry nodes or a custom
/// vertex-colored mesh, and looks the same from the fixed top-down camera.
enum LowPolyTextures {

    /// Bounded, because the key multiplies: 24 table colours times eight
    /// floor motifs is 192 entries at 1 MiB each, and nothing evicted. The
    /// working set is far smaller now that `GameScope` gives each game one
    /// colour, so a cap of 16 is generous and holds the ceiling at 16 MiB.
    private static var cache = BoundedImageCache(limit: 16)

    /// A grid of triangles, each filled with a slightly different shade of
    /// `baseColor` — the classic "low poly field" look from the reference
    /// images. Each grid cell is split into two triangles along alternating
    /// diagonals so the facets don't form an obvious repeating chevron.
    ///
    /// - Parameters:
    ///   - variation: how far each facet's brightness strays from the base,
    ///     as a fraction. Small values (0.06-0.12) read as subtle faceting;
    ///     larger values look like a deliberately stylized patchwork.
    static func facetedSurface(
        baseColor: UIColor,
        variation: CGFloat = 0.10,
        columns: Int = 14,
        rows: Int = 14,
        pixelSize: CGFloat = 512,
        // Defaults to pixelSize (square). Set for wide surfaces like the
        // score bar, so facets stay roughly equilateral instead of being
        // stretched into slivers when the image is scaled to fit.
        pixelHeight: CGFloat? = nil,
        seed: UInt64 = 12345,
        // A shape carried by the facets themselves — see FloorMotif. It
        // raises the grid resolution, because a numeral or a face needs
        // more than 16 cells a side to be legible.
        motif: FloorMotif = .none
    ) -> UIImage {
        let h = pixelHeight ?? pixelSize
        let columns = motif.grid ?? columns
        let rows = motif.grid ?? rows
        let key = "\(baseColor)-\(variation)-\(columns)x\(rows)-\(pixelSize)x\(h)-\(seed)-\(motif.rawValue)"
        if let cached = cache.value(key) { return cached }

        let size = CGSize(width: pixelSize, height: h)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        // Seeded generator so a given surface looks identical every launch
        // — a floor that re-randomizes its facets on every new game would
        // be distracting rather than characterful.
        var rng = SeededGenerator(seed: seed)

        // Built once, not per facet: `FloorMotif.shapes` constructs every
        // UIBezierPath it returns, and a 30x30 grid asks 1,800 times.
        let shapes = MotifShapes(motif: motif)

        let cellW = pixelSize / CGFloat(columns)
        let cellH = h / CGFloat(rows)

        let image = renderer.image { ctx in
            baseColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            for row in 0..<rows {
                for col in 0..<columns {
                    let x = CGFloat(col) * cellW
                    let y = CGFloat(row) * cellH

                    let tl = CGPoint(x: x, y: y)
                    let tr = CGPoint(x: x + cellW, y: y)
                    let bl = CGPoint(x: x, y: y + cellH)
                    let br = CGPoint(x: x + cellW, y: y + cellH)

                    // Alternate the split diagonal per cell so the facets
                    // read as an irregular field rather than a uniform
                    // sawtooth pattern.
                    let flip = (row + col) % 2 == 0
                    let triangles: [[CGPoint]] = flip
                        ? [[tl, tr, bl], [tr, br, bl]]
                        : [[tl, tr, br], [tl, br, bl]]

                    // Resolved once per cell rather than per triangle: the
                    // shapes are the same either way, and building them is
                    // the only part of this loop that is not arithmetic.
                    for tri in triangles {
                        var delta = (CGFloat(rng.nextUnit()) * 2 - 1) * variation
                        // The motif is a tonal STEP on the facet, not a
                        // shape drawn over it — which is what keeps it in
                        // the low-poly style rather than on top of it.
                        if motif != .none {
                            let centre = CGPoint(
                                x: (tri[0].x + tri[1].x + tri[2].x) / 3 / pixelSize,
                                y: (tri[0].y + tri[1].y + tri[2].y) / 3 / h
                            )
                            delta += shapes.lift(at: centre)
                        }
                        // .set() sets BOTH fill and stroke. Using
                        // .setFill() alone left the stroke at its default
                        // black, so the seam-closing stroke below outlined
                        // every facet in heavy black lines instead of
                        // blending invisibly into the fill.
                        shade(baseColor, by: delta).set()

                        let path = UIBezierPath()
                        path.move(to: tri[0])
                        path.addLine(to: tri[1])
                        path.addLine(to: tri[2])
                        path.close()
                        // Slight overdraw in the SAME colour as the fill:
                        // adjacent fills otherwise leave hairline seams
                        // from antialiasing along shared edges. The stroke
                        // exists only to cover those seams, so it must
                        // never be visible in its own right.
                        path.lineWidth = 1
                        path.fill()
                        path.stroke()
                    }
                }
            }
        }

        cache.insert(image, for: key)
        return image
    }

    /// Low-poly paper: aged off-white stock, faceted like everything else.
    ///
    /// A third generator beside `facetedSurface` and `woodSurface`, and it
    /// exists for the same reason wood does — the field generator is wrong
    /// for it. Wood needed direction; paper needs the opposite: almost no
    /// variation at all, because a sheet is flat and facets that read as
    /// terrain read as a stained wall.
    ///
    /// **Paper in the low-poly language, not photographic fibre.** Three
    /// passes, each doing one job:
    ///
    ///  1. Fine facets at very low variation — the tooth of the stock.
    ///  2. A coarser pass at low opacity — the uneven mottling that makes
    ///     a sheet look aged rather than new.
    ///  3. A darkening toward the edges, so a sheet has a soft border
    ///     instead of stopping dead. That is the "old" of old paper, done
    ///     with tone rather than with torn edges or foxing, which would
    ///     compete with whatever is printed on it.
    static func paperSurface(
        baseColor: UIColor = UIColor(hex: "#E9DFC6"),
        variation: CGFloat = 0.035,
        mottle: CGFloat = 0.055,
        edgeShade: CGFloat = 0.20,
        columns: Int = 26,
        pixelSize: CGFloat = 512,
        pixelHeight: CGFloat? = nil,
        seed: UInt64 = 30712
    ) -> UIImage {
        let h = pixelHeight ?? pixelSize
        let key = "paper-\(baseColor)-\(variation)-\(mottle)-\(edgeShade)"
            + "-\(columns)-\(pixelSize)x\(h)-\(seed)"
        if let cached = cache.value(key) { return cached }

        let size = CGSize(width: pixelSize, height: h)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let rows = max(1, Int((CGFloat(columns) * h / pixelSize).rounded()))
        let image = renderer.image { _ in
            // 1 and 2: the fine tooth, with coarse mottling laid over it.
            facets(size: size, base: baseColor,
                   columns: columns, rows: rows,
                   variation: variation, seed: seed)
            facets(size: size, base: baseColor,
                   columns: max(2, columns / 5), rows: max(2, rows / 5),
                   variation: mottle, seed: seed &+ 1, alpha: 0.5)

            // 3: the edges, drawn as a band of increasingly dark frames
            // rather than a gradient — a gradient is a photographic tool
            // and would be the one smooth thing on a faceted surface.
            let steps = 14
            let inset = min(size.width, size.height) * 0.10 / CGFloat(steps)
            for step in 0..<steps {
                let fraction = 1 - CGFloat(step) / CGFloat(steps)
                UIColor.black.withAlphaComponent(edgeShade * fraction * 0.16).setStroke()
                let rect = CGRect(origin: .zero, size: size)
                    .insetBy(dx: inset * CGFloat(step), dy: inset * CGFloat(step))
                let path = UIBezierPath(rect: rect)
                path.lineWidth = inset * 2
                path.stroke()
            }
        }

        cache.insert(image, for: key)
        return image
    }

    /// One pass of flat-shaded triangles, shared by the paper's tooth and
    /// its mottling.
    ///
    /// Split out rather than copied because the two passes differ only in
    /// cell size, variation and opacity — and a second hand-written facet
    /// loop is a second place for the diagonal-alternation trick to drift.
    private static func facets(size: CGSize, base: UIColor,
                               columns: Int, rows: Int,
                               variation: CGFloat, seed: UInt64,
                               alpha: CGFloat = 1) {
        var rng = SeededGenerator(seed: seed)
        let cellW = size.width / CGFloat(columns)
        let cellH = size.height / CGFloat(rows)

        for row in 0..<rows {
            for col in 0..<columns {
                let x = CGFloat(col) * cellW
                let y = CGFloat(row) * cellH
                let tl = CGPoint(x: x, y: y)
                let tr = CGPoint(x: x + cellW, y: y)
                let bl = CGPoint(x: x, y: y + cellH)
                let br = CGPoint(x: x + cellW, y: y + cellH)
                let flip = (row + col) % 2 == 0
                let triangles: [[CGPoint]] = flip
                    ? [[tl, tr, bl], [tr, br, bl]]
                    : [[tl, tr, br], [tl, br, bl]]

                for tri in triangles {
                    let delta = (CGFloat(rng.nextUnit()) * 2 - 1) * variation
                    shade(base, by: delta).withAlphaComponent(alpha).set()
                    let path = UIBezierPath()
                    path.move(to: tri[0])
                    path.addLine(to: tri[1])
                    path.addLine(to: tri[2])
                    path.close()
                    // Same overdraw as facetedSurface: adjacent fills leave
                    // hairline seams from antialiasing otherwise.
                    path.lineWidth = 1
                    path.fill()
                    path.stroke()
                }
            }
        }
    }

    /// Low-poly wood: horizontal plank bands, each split into long
    /// shallow triangles running WITH the grain.
    ///
    /// Deliberately not the same generator as `facetedSurface`. That one
    /// makes roughly equilateral triangles, which reads as crystal or
    /// terrain — fine for a field, wrong for timber. Wood's visual
    /// signature is strong directionality: long parallel bands with
    /// lengthwise variation and hard divisions between planks. So the
    /// cells here are wide and short, split along their long axis, and
    /// each plank carries its own base tone so the seams between boards
    /// stay legible.
    static func woodSurface(
        baseColor: UIColor,
        plankVariation: CGFloat = 0.14,
        shardVariation: CGFloat = 0.05,
        planks: Int = 5,
        shardsPerPlank: Int = 14,
        pixelSize: CGFloat = 1024,
        pixelHeight: CGFloat = 256,
        seed: UInt64 = 4242
    ) -> UIImage {
        let key = "wood-\(baseColor)-\(planks)x\(shardsPerPlank)-\(pixelSize)x\(pixelHeight)-\(seed)"
        if let cached = cache.value(key) { return cached }

        let size = CGSize(width: pixelSize, height: pixelHeight)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var rng = SeededGenerator(seed: seed)

        let plankH = pixelHeight / CGFloat(planks)
        let shardW = pixelSize / CGFloat(shardsPerPlank)

        let image = renderer.image { ctx in
            baseColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            for p in 0..<planks {
                // Per-plank tone first, so boards read as distinct pieces
                // of timber rather than one continuous noisy surface.
                let plankDelta = (CGFloat(rng.nextUnit()) * 2 - 1) * plankVariation
                let plankColor = shade(baseColor, by: plankDelta)
                let y = CGFloat(p) * plankH

                for sIdx in 0..<shardsPerPlank {
                    let x = CGFloat(sIdx) * shardW
                    let tl = CGPoint(x: x, y: y)
                    let tr = CGPoint(x: x + shardW, y: y)
                    let bl = CGPoint(x: x, y: y + plankH)
                    let br = CGPoint(x: x + shardW, y: y + plankH)
                    // Alternating diagonal keeps the grain from forming an
                    // obvious repeating zigzag along the plank.
                    let flip = (sIdx + p) % 2 == 0
                    let tris: [[CGPoint]] = flip
                        ? [[tl, tr, bl], [tr, br, bl]]
                        : [[tl, tr, br], [tl, br, bl]]
                    for tri in tris {
                        let d = (CGFloat(rng.nextUnit()) * 2 - 1) * shardVariation
                        shade(plankColor, by: d).set()
                        let path = UIBezierPath()
                        path.move(to: tri[0]); path.addLine(to: tri[1])
                        path.addLine(to: tri[2]); path.close()
                        path.lineWidth = 1
                        path.fill(); path.stroke()
                    }
                }

                // Hard seam between boards.
                shade(baseColor, by: -0.30).setStroke()
                let seam = UIBezierPath()
                seam.move(to: CGPoint(x: 0, y: y))
                seam.addLine(to: CGPoint(x: pixelSize, y: y))
                seam.lineWidth = 2
                seam.stroke()
            }
        }
        cache.insert(image, for: key)
        return image
    }

    /// Brightens (positive) or darkens (negative) a color by a fraction,
    /// working in HSB so hue stays put and only the value shifts — mixing
    /// toward white/black in RGB would wash out the saturation and make
    /// facets look dusty rather than shaded.
    private static func shade(_ color: UIColor, by delta: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
        return UIColor(hue: h, saturation: s, brightness: max(0, min(1, b + delta)), alpha: a)
    }
}

/// A motif's shapes, built once and asked many times.
///
/// `FloorMotif.shapes` constructs every `UIBezierPath` it returns, and the
/// facet loop asks 1,800 times per texture. Holding them costs one small
/// array and turns that into 1,800 hit tests instead of 1,800 rebuilds.
private struct MotifShapes {
    private let shapes: [FloorMotif.Shape]

    init(motif: FloorMotif) {
        shapes = motif.shapes
    }

    /// Later shapes win, so detail sits on the mass it belongs to.
    func lift(at point: CGPoint) -> CGFloat {
        var value: CGFloat = 0
        for shape in shapes where shape.path.contains(point) {
            value = shape.lift
        }
        return value
    }
}

/// A texture cache that cannot grow without limit.
///
/// Every generated-image cache in this app was a plain dictionary that only
/// ever grew. Individually none of them looked expensive; together their
/// ceiling was about 286 MiB, because the keys multiply — colours times
/// motifs, colourways times numerals — and nothing ever evicted.
///
/// `DieMaterialFactory` hit this first and documents it at its
/// `grainTextureCache`: "the cache had no eviction and 15 colorways x 8
/// grain variants means it grows toward 120 entries at 1 MB each". The
/// best answer is to take the multiplying dimension out of the key, which
/// is what that file did and what `DieFaceLabels` now does too. This is the
/// backstop for what is left.
///
/// Oldest-first rather than least-recently-used: the cost of a miss is one
/// Core Graphics render of a texture that is already only built when a
/// scene is assembled, so the bookkeeping an LRU needs would cost more
/// than it saves.
struct BoundedImageCache {
    private var images: [String: UIImage] = [:]
    private var order: [String] = []
    private let limit: Int

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func value(_ key: String) -> UIImage? { images[key] }

    mutating func insert(_ image: UIImage, for key: String) {
        guard images[key] == nil else { return }
        images[key] = image
        order.append(key)

        while order.count > limit {
            // The evicted image is NOT necessarily freed: a material still
            // showing it holds its own reference, which is correct — this
            // caps what is held on the cache's behalf, not what is on
            // screen.
            images.removeValue(forKey: order.removeFirst())
        }
    }

    mutating func image(_ key: String, _ build: () -> UIImage) -> UIImage {
        if let hit = value(key) { return hit }
        let image = build()
        insert(image, for: key)
        return image
    }
}
