import UIKit
import SwiftUI
import SceneKit

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

    /// Bounded, because the key multiplies: 24 table colours times the
    /// surfaces that ask for one, at up to 1 MiB each, and nothing evicted.
    /// The working set is smaller again now that the tray floor is a shader
    /// rather than a cached image, so a cap of 16 holds the ceiling at 16 MiB
    /// with room to spare.
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
        seed: UInt64 = 12345
    ) -> UIImage {
        let h = pixelHeight ?? pixelSize
        let key = "\(baseColor)-\(variation)-\(columns)x\(rows)-\(pixelSize)x\(h)-\(seed)"
        if let cached = cache.value(key) { return cached }

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

/// A texture cache that cannot grow without limit.
///
/// Every generated-image cache in this app was a plain dictionary that only
/// ever grew. Individually none of them looked expensive; together their
/// ceiling was about 286 MiB, because the keys multiply — colours times
/// surfaces, colourways times numerals — and nothing ever evicted.
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


// ---------------------------------------------------------------------
// The flowing floor lives here rather than in a SmokeFloor.swift of its
// own. This project is assembled by hand in Swift Playgrounds, which does
// NOT pick up a new file on its own — and seventeen files reference
// SmokeFloor, so a copy that never received the file fails seventeen
// times over with "cannot find SmokeFloor in scope".
//
// Keeping every stage of this rollout to REPLACEMENTS ONLY is the whole
// point: if a stage fails, it is the code in that stage, not a file
// somebody forgot to add.
//
// It belongs beside the other surface generators anyway — this file's
// job is producing the playfield's material, which is what this is.
// ---------------------------------------------------------------------

/// The rolling area: a domain-warped noise field, ordered-dithered and crushed
/// to exactly four tones, moving on a closed thirty-second path.
///
/// This is the one animated material in the app. Everything else — the wood,
/// the dice, the board art — is a CoreGraphics image generated once and handed
/// to `material.diffuse.contents`. The floor cannot be, because it has to move
/// without repeating in a way anyone notices, and 24 table colours times enough
/// frames to look smooth is not a texture budget worth spending.
///
/// The reference this is built against is two GIFs, and they are unusually
/// specific: both carry a four-entry colour table, and their tone boundaries
/// are stippled rather than blended. That stippling is the entire look. It is
/// also the part that is easy to get wrong — see `smokeTone` below.
///
/// `tools_smoke_preview.py` is the same maths in Python, and the only way to
/// see this before an iPad does; `tools_smoke_verify.py` asserts the two agree
/// number for number. Change a constant here, change it there.
enum SmokeFloor {

    // MARK: - The shape of the thing

    /// One full cycle, after which the field is EXACTLY where it started.
    ///
    /// Not approximately. Time enters the field only as a point travelling a
    /// circle (see `surfaceModifier`), so every term is periodic in this and
    /// the composite is too.
    static let loopSeconds: Float = 30.0

    /// Texels per dither cell — the apparent pixel size of the stipple.
    static let pixelSize: Float = 4.0

    // MARK: - The shader

    /// Assigned to `material.shaderModifiers[.surface]`.
    ///
    /// A string, compiled by SceneKit at runtime, which is what makes this
    /// possible at all: this project is built in Swift Playgrounds on an iPad
    /// and cannot add a `.metal` file to its target. There is no build step to
    /// hook, so the shader has to arrive as data.
    ///
    /// Three things in here are deliberate and would be easy to "simplify"
    /// into something that no longer works:
    ///
    /// 1. **The Bayer matrix is arithmetic, not an array.** The Darkbringer
    ///    reference shader carries it as 64 literals and ships `bayer8x8.png`
    ///    besides. A file-scope constant array is the least portable thing you
    ///    can put in a shader modifier, which SceneKit translates rather than
    ///    compiling as written. The recursive form needs no array, no texture
    ///    and no bit twiddling, and it is not an approximation — checked cell
    ///    by cell against the literal matrix it agrees exactly, to 0.0.
    ///
    /// 2. **The dither is added to the value BEFORE it is quantised.**
    ///    Quantising first and sprinkling noise after gives noise over flat
    ///    contour bands, which reads as a dirty gradient. Offsetting the value
    ///    first makes the BOUNDARY itself break up into pixels, which is what
    ///    the references actually show and the only version that reads as
    ///    pixel art.
    ///
    /// 3. **The final sample carries its own orbit.** It is tempting to move
    ///    only the warp layers and let the field ride along. That shipped once
    ///    and was wrong: with the base field pinned in space, anywhere the warp
    ///    gradient was weak simply did not move, so the floor churned in one
    ///    band and sat still everywhere else.
    static let surfaceModifier: String = """
    #pragma arguments
    float3 smokeToneA;
    float3 smokeToneB;
    float3 smokeToneC;
    float3 smokeToneD;

    #pragma declaration
    float smokeHash(float2 p) {
        return fract(sin(p.x * \(hashX) + p.y * \(hashY)) * \(hashScale));
    }

    float smokeNoise(float2 p) {
        float2 i = floor(p);
        float2 f = p - i;
        float2 u = f * f * (3.0 - 2.0 * f);
        float a = smokeHash(i);
        float b = smokeHash(i + float2(1.0, 0.0));
        float c = smokeHash(i + float2(0.0, 1.0));
        float d = smokeHash(i + float2(1.0, 1.0));
        return a + (b - a) * u.x + (c - a) * u.y * (1.0 - u.x)
                 + (d - b) * u.x * u.y;
    }

    // Normalised to 0..1. Without the divide the sum tops out near 0.97 and
    // sits around 0.49, so the four tones split a band far narrower than the
    // posterise step and two of them barely appear.
    float smokeFbm(float2 p) {
        float total = 0.0;
        float amp = 0.5;
        float freq = 1.0;
        float norm = 0.0;
        for (int i = 0; i < \(octaves); i++) {
            total += amp * smokeNoise(p * freq);
            norm += amp;
            freq *= \(lacunarity);
            amp *= \(gain);
        }
        return total / norm;
    }

    float smokeBayer2(float2 a) {
        float2 f = floor(a);
        return fract(f.x / 2.0 + f.y * f.y * 0.75);
    }

    float smokeBayer8(float2 a) {
        float b4 = smokeBayer2(0.25 * a) * 0.25 + smokeBayer2(0.5 * a);
        return b4 * 0.25 + smokeBayer2(a);
    }

    #pragma body
    float2 uv = _surface.diffuseTexcoord;

    // Snap to the dither grid first. The field and the threshold are both
    // constant across a cell by construction, so sampling per-fragment would
    // compute an identical five-octave warp many times over and then throw
    // the difference away.
    float2 cell = floor(uv * \(cellsAcross));

    float2 p;
    p.x = (cell.x + 0.5) / \(cellsAcross) * \(fieldScale) + \(originX);
    p.y = (cell.y + 0.5) / \(cellsAcross) * \(fieldScale) * \(fieldAspect) + \(originY);

    // scn_frame.time, not u_time. `u_time` is the OpenGL ES spelling, and
    // SceneKit has not rendered with OpenGL on iOS for years — a shader
    // modifier is translated into Metal, where the scene-wide uniforms
    // arrive in `scn_frame` (an SCNSceneBuffer) and time is a member of
    // it. `u_time` compiles nowhere and took the whole material with it:
    //
    //   [SceneKit] Error: FATAL ERROR : failed compiling shader:
    //   error: use of undeclared identifier 'u_time'
    //
    // Everything else in here was already Metal — float2/float3/float4
    // rather than vec2/vec3/vec4 — which is exactly why one OpenGL-only
    // identifier was easy to miss.
    float ang = 6.2831853 * (scn_frame.time / \(loopSeconds));
    float2 oq = float2(cos(ang), sin(ang)) * \(orbitQ);
    float2 orr = float2(cos(ang + \(phaseR)), sin(ang + \(phaseR))) * \(orbitR);
    float2 onn = float2(cos(ang + \(phaseN)), sin(ang + \(phaseN))) * \(orbitN);

    float qx = smokeFbm(float2(p.x + oq.x, p.y + oq.y));
    float qy = smokeFbm(float2(p.x + 5.2 - oq.y, p.y + 1.3 + oq.x));

    float rx = smokeFbm(float2(p.x + \(warpA) * qx + 1.7 + orr.x,
                               p.y + \(warpA) * qy + 9.2 + orr.y));
    float ry = smokeFbm(float2(p.x + \(warpA) * qx + 8.3 - orr.y,
                               p.y + \(warpA) * qy + 2.8 + orr.x));

    float n = smokeFbm(float2(p.x + \(warpB) * rx + onn.x,
                              p.y + \(warpB) * ry + onn.y));

    n = clamp((n - 0.5) * \(contrast) + 0.5, 0.0, 1.0);

    // Dither the VALUE, then quantise. See note 2 above.
    float limit = smokeBayer8(cell) + 0.5 / 64.0;
    n += (limit - 0.5) * (\(dither) / \(Float(levels - 1)));

    float step = clamp(floor(n * \(Float(levels))), 0.0, \(Float(levels - 1)));

    float3 tone = smokeToneA;
    tone = (step > 0.5) ? smokeToneB : tone;
    tone = (step > 1.5) ? smokeToneC : tone;
    tone = (step > 2.5) ? smokeToneD : tone;

    _surface.diffuse = float4(tone, 1.0);
    """

    // MARK: - The constants the shader is built from
    //
    // Interpolated into the GLSL above rather than written twice, so there is
    // one place to change each of them and `tools_smoke_verify.py` has one
    // place to read them from.

    static let hashX: Float = 127.1
    static let hashY: Float = 311.7
    static let hashScale: Float = 43758.5453

    static let octaves = 5
    static let lacunarity: Float = 2.0
    static let gain: Float = 0.5

    static let originX: Float = 17.3
    static let originY: Float = 9.1

    static let fieldScale: Float = 1.5
    static let fieldAspect: Float = 0.55
    static let contrast: Float = 2.90
    static let levels = 4
    static let dither: Float = 0.70

    static let warpA: Float = 2.4
    static let warpB: Float = 1.8

    static let orbitQ: Float = 0.45
    static let orbitR: Float = 0.55
    static let orbitN: Float = 0.22
    static let phaseR: Float = 2.1
    static let phaseN: Float = 4.3

    /// Dither cells across the floor. The shader works in UV, so this is what
    /// turns `pixelSize` into something it can use.
    static let cellsAcross: Float = 256.0

    // MARK: - Four tones from one swatch

    static let rampSpread: CGFloat = 0.24
    static let rampSpreadMin: CGFloat = 0.12
    static let rampFloor: CGFloat = 0.045
    static let rampCeil: CGFloat = 0.94
    static let rampSatLift: CGFloat = 0.05
    static let rampBias: CGFloat = 0.55

    /// The four tones, darkest first, hung DOWNWARD from the chosen swatch.
    ///
    /// The brightest of the four IS the swatch; the other three shade away
    /// beneath it. Centring the band on the swatch instead — the obvious first
    /// try — quietly betrays the picker at the dark end: "Onyx" (`#14140F`)
    /// came back as a legible but unmistakably olive-grey floor, because the
    /// clamp that stops four near-blacks merging had slid the whole band
    /// upward. Anchoring the top means the colour you picked is the colour you
    /// mostly see, at every one of the 24 swatches.
    ///
    /// The steps are NOT evenly spaced, which is `rampBias`. Sorted by
    /// luminance, red-wave.gif runs #CD0000 then #FF0000 #FF3535 #FF4F4F, and
    /// reggie.gif runs #F0243C #F21D45 #FA6278 #FFFFFF — in both, one tone
    /// sits well clear of the other three, which cluster. That is what makes
    /// them read as a graphic two-tone with shading rather than as a four-step
    /// gradient, and it is what keeps the dither legible now that the whole
    /// span is only 0.24 of brightness.
    static func ramp(from color: UIColor) -> [UIColor] {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return Array(repeating: color, count: levels)
        }

        var hi = min(rampCeil, b)
        let spread = rampSpreadMin + (rampSpread - rampSpreadMin) * hi
        var lo = hi - spread
        if lo < rampFloor {
            lo = rampFloor
            hi = max(hi, lo + rampSpreadMin)
        }

        return (0..<levels).map { i in
            let f = pow(CGFloat(i) / CGFloat(levels - 1), rampBias)
            return UIColor(hue: h,
                           saturation: max(0, s - rampSatLift * f),
                           brightness: lo + (hi - lo) * f,
                           alpha: 1.0)
        }
    }

    /// The darkest tone — what anything behind or beside the floor is painted,
    /// so a sliver of backdrop reads as part of the field rather than as a
    /// hole in it. Black is never the backstop.
    static func backdrop(from color: UIColor) -> UIColor {
        ramp(from: color).first ?? color
    }

    /// The same, for SwiftUI, from whatever the player has picked right now.
    static var backdropColor: Color {
        Color(backdrop(from: AppTheme.shared.floorBaseColor))
    }

    // MARK: - Applying it

    /// Puts the field on a material, with a static floor underneath it.
    ///
    /// Order matters and is the whole safety story. SceneKit reports a shader
    /// modifier that fails to compile asynchronously, on the render thread,
    /// rather than throwing — so there is nothing to catch and nothing to
    /// check. Instead the still image goes on FIRST and the shader is layered
    /// over it: if the shader compiles it overwrites the diffuse result and
    /// the still is never seen, and if it does not, the still is already
    /// there. Either way the tray is a four-tone floor and never a black
    /// rectangle.
    static func apply(to material: SCNMaterial, color: UIColor) {
        let tones = ramp(from: color)

        material.diffuse.contents = fallbackTexture(tones: tones)
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        // .lambert, not .physicallyBased: flat matte, no specular, so the
        // floor shades under the existing key/ambient rig the same way the
        // dice do.
        material.lightingModel = .lambert
        material.shaderModifiers = [.surface: surfaceModifier]

        applyTones(tones, to: material)
    }

    /// Re-colours an already-built floor when the player picks a new swatch.
    ///
    /// This is four small uploads and a still image, where the old faceted
    /// floor had to re-run a full CoreGraphics render of thousands of
    /// triangles for the same result.
    static func retint(_ material: SCNMaterial, color: UIColor) {
        let tones = ramp(from: color)
        material.diffuse.contents = fallbackTexture(tones: tones)
        applyTones(tones, to: material)
    }

    private static func applyTones(_ tones: [UIColor], to material: SCNMaterial) {
        let names = ["smokeToneA", "smokeToneB", "smokeToneC", "smokeToneD"]
        for (name, tone) in zip(names, tones) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            tone.getRed(&r, green: &g, blue: &b, alpha: &a)
            material.setValue(NSValue(scnVector3: SCNVector3(Float(r), Float(g), Float(b))),
                              forKey: name)
        }
    }

    // MARK: - The still, for when the shader does not arrive

    /// One frame of the same field, on the CPU.
    ///
    /// Deliberately not a good imitation of the animation — it is the same
    /// maths at t = 0, so a floor that falls back to it is still recognisably
    /// the right floor in the right four colours, just still. Cached, because
    /// `retint` asks for it on every swatch change.
    static func fallbackTexture(tones: [UIColor]) -> UIImage {
        let key = tones.map { $0.description }.joined(separator: "|")
        if let hit = stillCache[key] { return hit }

        let cells = 128
        let size = CGSize(width: cells, height: cells)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1

        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            for cy in 0..<cells {
                for cx in 0..<cells {
                    let u = (Float(cx) + 0.5) / Float(cells)
                    let v = (Float(cy) + 0.5) / Float(cells)
                    let step = toneIndex(u: u, v: v, t: 0, cx: cx, cy: cy)
                    tones[step].setFill()
                    ctx.fill(CGRect(x: cx, y: cy, width: 1, height: 1))
                }
            }
        }

        if stillCache.count > 8 { stillCache.removeAll() }
        stillCache[key] = image
        return image
    }

    private static var stillCache: [String: UIImage] = [:]

    // MARK: - The same field, in Swift
    //
    // A third copy of the maths, after the GLSL and the Python, which is one
    // more than anybody wants. It exists because the fallback has to look like
    // the shader it is standing in for, and `tools_smoke_verify.py` checks all
    // three against each other rather than trusting that.

    private static func hash2(_ x: Float, _ y: Float) -> Float {
        let v = sin(x * hashX + y * hashY) * hashScale
        return v - floor(v)
    }

    private static func noise(_ x: Float, _ y: Float) -> Float {
        let ix = floor(x), iy = floor(y)
        let fx = x - ix, fy = y - iy
        let ux = fx * fx * (3.0 - 2.0 * fx)
        let uy = fy * fy * (3.0 - 2.0 * fy)
        let a = hash2(ix, iy)
        let b = hash2(ix + 1, iy)
        let c = hash2(ix, iy + 1)
        let d = hash2(ix + 1, iy + 1)
        return a + (b - a) * ux + (c - a) * uy * (1 - ux) + (d - b) * ux * uy
    }

    private static func fbm(_ x: Float, _ y: Float) -> Float {
        var total: Float = 0, amp: Float = 0.5, freq: Float = 1, norm: Float = 0
        for _ in 0..<octaves {
            total += amp * noise(x * freq, y * freq)
            norm += amp
            freq *= lacunarity
            amp *= gain
        }
        return total / norm
    }

    private static func bayer2(_ x: Float, _ y: Float) -> Float {
        let v = floor(x) / 2.0 + floor(y) * floor(y) * 0.75
        return v - floor(v)
    }

    private static func bayer8(_ x: Float, _ y: Float) -> Float {
        let b4 = bayer2(0.25 * x, 0.25 * y) * 0.25 + bayer2(0.5 * x, 0.5 * y)
        return b4 * 0.25 + bayer2(x, y)
    }

    static func field(u: Float, v: Float, t: Float) -> Float {
        let x = u * fieldScale + originX
        let y = v * fieldScale * fieldAspect + originY

        let ang = 2 * Float.pi * (t / loopSeconds)
        let ca = cos(ang), sa = sin(ang)
        let cr = cos(ang + phaseR), sr = sin(ang + phaseR)
        let cn = cos(ang + phaseN), sn = sin(ang + phaseN)

        let qx = fbm(x + orbitQ * ca, y + orbitQ * sa)
        let qy = fbm(x + 5.2 - orbitQ * sa, y + 1.3 + orbitQ * ca)

        let rx = fbm(x + warpA * qx + 1.7 + orbitR * cr,
                     y + warpA * qy + 9.2 + orbitR * sr)
        let ry = fbm(x + warpA * qx + 8.3 - orbitR * sr,
                     y + warpA * qy + 2.8 + orbitR * cr)

        let n = fbm(x + warpB * rx + orbitN * cn,
                    y + warpB * ry + orbitN * sn)

        return min(1, max(0, (n - 0.5) * contrast + 0.5))
    }

    static func toneIndex(u: Float, v: Float, t: Float, cx: Int, cy: Int) -> Int {
        var n = field(u: u, v: v, t: t)
        let limit = bayer8(Float(cx), Float(cy)) + 0.5 / 64.0
        n += (limit - 0.5) * (dither / Float(levels - 1))
        let i = Int(n * Float(levels))
        return i < 0 ? 0 : (i > levels - 1 ? levels - 1 : i)
    }
}
