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

    private static var cache: [String: UIImage] = [:]

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
        seed: UInt64 = 12345
    ) -> UIImage {
        let h = pixelHeight ?? pixelSize
        let key = "\(baseColor)-\(variation)-\(columns)x\(rows)-\(pixelSize)x\(h)-\(seed)"
        if let cached = cache[key] { return cached }

        let size = CGSize(width: pixelSize, height: h)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        // Seeded generator so a given surface looks identical every launch
        // — a floor that re-randomizes its facets on every new game would
        // be distracting rather than characterful.
        var rng = SeededGenerator(seed: seed)

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

                    for tri in triangles {
                        let delta = (CGFloat(rng.nextUnit()) * 2 - 1) * variation
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

        cache[key] = image
        return image
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
        if let cached = cache[key] { return cached }

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
        cache[key] = image
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
