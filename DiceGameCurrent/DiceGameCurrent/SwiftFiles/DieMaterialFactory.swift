import UIKit
import SceneKit

// MARK: - Robust image loading

/// UIImage(named:) only reliably finds images that made it into a proper
/// asset catalog. In plain Xcode projects that's a safe assumption, but
/// Swift Playgrounds on iPad doesn't always route "Insert from"-added
/// images through an asset catalog the way Xcode does — the image is
/// still genuinely present in the bundle, but named: lookup alone can
/// return nil for it. Falling back to a direct file lookup covers both
/// cases without needing to know which one is actually happening. Still
/// used by DiceSceneEnvironment for the floor texture, even though the
/// die-body numbered-texture pipeline that used to live in this file has
/// been replaced by DieFaceLabels.
enum BundleImageLoader {
    static func load(named name: String) -> UIImage? {
        if let catalogImage = UIImage(named: name) {
            return catalogImage
        }
        guard let path = Bundle.main.path(forResource: name, ofType: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: path)
    }
}

// MARK: - Applying to a die node

enum DieMaterial {

    // Numerals are NOT part of this material. Baking them into the mesh
    // texture worked for d8 but never for d6/d10/d12, despite the UV data,
    // mesh format, and recoloring all verifying as correct — they moved to
    // DieFaceLabels (flat plane labels per face), which sidesteps mesh UV
    // mapping entirely. This material handles body color and grain only.

    /// ONE shared grayscale grain texture, not one baked per colorway.
    ///
    /// The previous version composited the body color and the grain into a
    /// single texture, cached under a colorway+variant key. That worked,
    /// but the cache had no eviction and 15 colorways x 8 grain variants
    /// means it grows toward 120 entries at 1 MB each — ~120 MB of texture
    /// memory accumulating across repeated games, for what is visually a
    /// 5% overlay.
    ///
    /// Instead: keep diffuse as the flat body color, and put the grain in
    /// the material's `multiply` channel as a single mostly-white
    /// grayscale image. Multiplying near-white over the body color darkens
    /// it only where the grain is, reproducing the same look. Per-die
    /// variation moves to `multiply.contentsTransform` (a UV offset/flip),
    /// which costs nothing and needs no extra texture. Net result: one
    /// 256x256 texture (~0.25 MB) for the entire game instead of up to
    /// 120 MB, and variation becomes free rather than cache-multiplying.
    private static var grainTextureCache: UIImage?

    /// Whether dice bodies carry the pixel-grain overlay at all.
    ///
    /// Off for the low-poly style. The grain is scanned photographic
    /// noise, and photographic detail is the opposite of what flat
    /// faceting is going for — with it on, the dice kept reading as the
    /// previous realistic styling even after the shading model changed.
    /// Flat solid colour lets the facet-to-facet lighting differences be
    /// the only surface detail, which is the whole point of the look.
    ///
    /// Flip to true to bring it back; nothing else needs changing.
    private static let applyGrainToDice = false

    /// How strongly the pixel-grain shows over the body color, when on.
    private static let grainOpacity: CGFloat = 0.05

    // MARK: Ordered dither

    /// How far a dark dither cell pulls the body colour down.
    ///
    /// MULTIPLY, not replace, and that is the whole reason the fifteen
    /// colourways survive this: every texel is either the body colour or the
    /// body colour scaled by (1 - this), so the hue never moves and one die
    /// stays exactly as tellable from another as it was. The floor gets
    /// posterised to four tones; the dice deliberately do NOT, because that
    /// palette is how you know which die you are looking at.
    ///
    /// 0.10, DOWN FROM 0.16 after looking at it on the iPad — which is the
    /// only place this could be judged, and the reason it shipped at 0.16
    /// first rather than waiting for a preview nobody could see on a device.
    /// At 0.16 the stipple read as too heavy over the body colours; at 0.10
    /// it is still unambiguously a stipple and stops competing with the
    /// numerals.
    ///
    /// Measured in tools_dice_preview.py, the worst any numeral drops to at
    /// this strength is 6.28:1 (#7CBD7B with its dark numeral), against a 3:1
    /// large-text bar — better than 0.16's 5.48:1, since a fainter dither
    /// takes less contrast away. Three colourways already sit under that bar
    /// FLAT, today, which this improves rather than causes.
    static let ditherStrength: CGFloat = 0.10

    /// How many dither cells run across one die face.
    ///
    /// The one number here that cannot be reasoned out — it is purely how
    /// many screen pixels a cell ends up covering on a real device, and too
    /// FINE is the failure that matters: a stipple below what the eye
    /// resolves stops reading as pixel art and becomes photographic noise,
    /// which is exactly what `applyGrainToDice = false` turned off.
    ///
    /// 20, UP FROM 14, after the first device test: at 14 a cell covered
    /// roughly 9px on a die at arm's length and read as too coarse — the
    /// pixels, not the die, were what you noticed. 20 puts a cell at about
    /// 6px, which is finer without crossing into the noise this comment
    /// warns about. If it ever does cross, the symptom is specific: the
    /// faces stop looking printed and start looking dirty.
    ///
    /// tools_dice_verify.py pins this to the preview's own grid
    /// (SWATCH / CELL), so the density on the sheet is always the density
    /// that ships — the two cannot drift.
    static let ditherCellsPerFace: CGFloat = 20

    /// One 8x8 Bayer matrix, white where the body shows through and grey
    /// where it is pulled down. Built once and shared by every die.
    private static var ditherTextureCache: UIImage?

    /// The standard 8x8 ordered-dither threshold matrix, 0..63.
    ///
    /// The same one SmokeFloor derives arithmetically in GLSL — written as a
    /// literal here because this runs once on the CPU, where a table is
    /// simply clearer than three nested recursions.
    private static let bayer8: [[Int]] = [
        [ 0, 32,  8, 40,  2, 34, 10, 42],
        [48, 16, 56, 24, 50, 18, 58, 26],
        [12, 44,  4, 36, 14, 46,  6, 38],
        [60, 28, 52, 20, 62, 30, 54, 22],
        [ 3, 35, 11, 43,  1, 33,  9, 41],
        [51, 19, 59, 27, 49, 17, 57, 25],
        [15, 47,  7, 39, 13, 45,  5, 37],
        [63, 31, 55, 23, 61, 29, 53, 21]
    ]

    /// The dither tile: exactly 8x8 texels, one per Bayer cell.
    ///
    /// Deliberately the smallest image that can express the pattern. It is
    /// magnified enormously on the die, which is what makes
    /// `magnificationFilter = .nearest` at the call site load-bearing rather
    /// than a nicety — with the default linear filter SceneKit interpolates
    /// between texels and the dither arrives as a soft grey wash, which is
    /// the one result that would look worse than no dither at all.
    private static func ditherTexture() -> UIImage? {
        if let cached = ditherTextureCache { return cached }

        let side = 8
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: format)

        let dark = UIColor(white: 1 - ditherStrength, alpha: 1)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            dark.setFill()
            for row in 0..<side {
                for col in 0..<side {
                    // A fixed half-duty threshold, which gives the regular
                    // checker the reference art uses rather than a gradient.
                    guard bayer8[row][col] >= 32 else { continue }
                    ctx.fill(CGRect(x: col, y: row, width: 1, height: 1))
                }
            }
        }
        ditherTextureCache = image
        return image
    }

    /// Distinct grain layouts, applied as UV offsets/flips rather than
    /// separate baked images, so this no longer multiplies texture memory.
    static let grainVariantCount = 8

    /// Mostly-white tile carrying the grain pattern, for the multiply
    /// channel. Built once and shared by every die.
    private static func grainTexture() -> UIImage? {
        if let cached = grainTextureCache { return cached }
        guard let grain = BundleImageLoader.load(named: "pix_texture") else { return nil }

        let side: CGFloat = 256
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { ctx in
            // White base: multiplying by white is a no-op, so anywhere the
            // grain doesn't darken, the body color passes through unchanged.
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Source is a wide 1280x64 strip; tile it rather than
            // stretching it into smears.
            let scale: CGFloat = 0.35
            let w = 1280 * scale
            let h = 64 * scale
            var y: CGFloat = 0
            while y < side {
                var x: CGFloat = 0
                while x < side {
                    // draw(in:blendMode:alpha:) rather than setting context
                    // alpha then calling plain draw(in:) — the latter came
                    // out fully opaque, since UIImage.draw(in:) doesn't
                    // reliably honor ambient CGContext alpha state.
                    grain.draw(in: CGRect(x: x, y: y, width: w, height: h),
                               blendMode: .normal, alpha: grainOpacity)
                    x += w
                }
                y += h
            }
        }

        grainTextureCache = image
        return image
    }

    /// UV transform giving each die its own slice of the shared grain
    /// tile. Offsets are deliberately non-integer multiples so variants
    /// sample genuinely different regions rather than landing on the same
    /// seam; the sign flips mirror the tile for additional variety.
    private static func grainTransform(variant: Int) -> SCNMatrix4 {
        let v = variant % grainVariantCount
        let offsetX = Float(v) * 0.37
        let offsetY = Float(v) * 0.61
        let flipX: Float = (v % 4 >= 2) ? -1 : 1
        let flipY: Float = (v % 2 == 1) ? -1 : 1
        let scale = SCNMatrix4MakeScale(flipX, flipY, 1)
        return SCNMatrix4Translate(scale, offsetX, offsetY, 0)
    }


    /// UV transform tiling the 8x8 dither across a face at the chosen cell
    /// density, offset per die so neighbouring dice do not land on the same
    /// phase and read as one printed sheet.
    ///
    /// The offsets are deliberately NOT required to land on whole cells, and
    /// the earlier claim that they do was wrong twice over — recorded here
    /// because a later round would otherwise trust it and "fix" working code.
    ///
    /// First, they do not: `SCNMatrix4Translate(m, tx, ty, tz)` concatenates
    /// the translation BEFORE `m`, the way `CATransform3DTranslate` does, so
    /// each offset is multiplied by `repeats` (14/8 = 1.75). The real step is
    /// 1.75 cells, not 1.
    ///
    /// Second, it does not matter: `.nearest` never interpolates between
    /// texels, so no UV offset — fractional or otherwise — can soften an
    /// edge. A fractional offset only shifts where cell boundaries fall on
    /// the face, which is precisely the de-phasing this exists to produce.
    ///
    /// Same shape as `grainTransform` above, whose offsets (0.37, 0.61) never
    /// pretended to be whole anything.
    private static func ditherTransform(variant: Int) -> SCNMatrix4 {
        let repeats = Float(ditherCellsPerFace / 8)
        let v = variant % grainVariantCount
        let scale = SCNMatrix4MakeScale(repeats, repeats, 1)
        return SCNMatrix4Translate(scale, Float(v % 4) / 8, Float(v / 4) / 8, 0)
    }

    static func apply(
        sides: Int,
        colorway: DieColorway,
        to node: SCNNode,
        rollsFaceNumber: Int? = nil,
        grainVariant: Int = 0,
        d4Style: DieFaceLabels.D4LabelStyle = .topRead
    ) {
        guard applyBodyMaterial(colorway: colorway, to: node, grainVariant: grainVariant) else { return }

        DieFaceLabels.addPermanentFaceNumbers(
            to: node,
            sides: sides,
            colorway: colorway,
            rollsFaceNumber: rollsFaceNumber,
            d4Style: d4Style
        )
    }

    /// Alternative D4 styling: no numerals at all. Two of the tetrahedron's
    /// four corners get a plain mark, the other two get nothing — since a
    /// tetrahedron always rests on a face with exactly one vertex pointing
    /// up, marking half the corners gives a 50/50 marked-vs-unmarked
    /// result on any roll, same idea as a coin flip rather than a 1-4
    /// numbered read. Not used by this game's own pool (still numbered
    /// d4/d6/d8/d10/d12 throughout) — a ready-to-use alternative for
    /// wherever the wider project wants a binary-outcome d4 instead.
    ///
    /// Body material setup is identical to the numbered apply(sides:...)
    /// above (same color, grain, shading model) — only the face
    /// decoration differs, so that part is shared via applyBodyMaterial
    /// rather than duplicated.
    static func applyCornerMarkD4(colorway: DieColorway, to node: SCNNode, grainVariant: Int = 0) {
        guard applyBodyMaterial(colorway: colorway, to: node, grainVariant: grainVariant) else { return }

        DieFaceLabels.addD4CornerMarks(to: node, colorway: colorway)
    }

    /// Body color/grain/shading setup shared by both apply(sides:...) and
    /// applyCornerMarkD4 — everything except the face decoration, which is
    /// the one thing that differs between a numbered die and the
    /// corner-marked D4 variant. Returns false (having done nothing) if
    /// the node has no geometry yet, matching apply(sides:...)'s original
    /// early-return behavior.
    @discardableResult
    private static func applyBodyMaterial(colorway: DieColorway, to node: SCNNode, grainVariant: Int) -> Bool {
        guard node.geometry != nil else { return false }

        let material = SCNMaterial()
        material.diffuse.contents = UIColor(hex: colorway.bodyHex)
        // Grain lives in the multiply channel over a flat body color,
        // rather than being baked into a per-colorway diffuse texture —
        // see grainTexture()'s doc comment for why. Silently skipped if
        // the grain image is missing from the bundle, leaving a clean
        // flat-colored die rather than failing.
        if applyGrainToDice, let grain = grainTexture() {
            material.multiply.contents = grain
            material.multiply.wrapS = .repeat
            material.multiply.wrapT = .repeat
            material.multiply.contentsTransform = grainTransform(variant: grainVariant)
        } else if let dither = ditherTexture() {
            // The ordered stipple, in the same channel the grain used and
            // for the opposite reason: the grain was scanned photographic
            // noise and fought the flat faceting, where this IS the flat
            // grammar — the floor's own 8x8 Bayer, on the dice.
            //
            // It cannot reach the numerals, and that is structural rather
            // than careful: DieFaceLabels puts every numeral on its own
            // SCNPlane child node with its own material, while this sets
            // `node.geometry?.materials = [material]` on the die body
            // alone. There is no path from this channel to a numeral.
            material.multiply.contents = dither
            material.multiply.wrapS = .repeat
            material.multiply.wrapT = .repeat
            // Nearest, not linear. The tile is 8x8 texels magnified across a
            // whole face, so the default filter would interpolate between
            // them and deliver a soft grey wash instead of hard cells — the
            // one outcome worse than not doing this at all.
            material.multiply.magnificationFilter = .nearest
            material.multiply.minificationFilter = .nearest
            material.multiply.mipFilter = .none
            material.multiply.contentsTransform = ditherTransform(variant: grainVariant)
        }
        // .lambert for the low-poly style: flat matte shading, no
        // specular highlight. The dice meshes are already genuinely
        // low-poly (8-36 triangles) with flat per-triangle normals, so
        // they were always faceted — it was PBR's glossiness that made
        // them read as smooth realistic objects rather than faceted ones.
        // roughness/metalness are PBR-only and no longer apply.
        // .blinn rather than .lambert for the dice specifically. Lambert
        // is purely diffuse — no specular term at all — so it physically
        // cannot produce a highlight. Blinn keeps the flat per-facet
        // shading the low-poly look depends on while adding a controllable
        // specular, which is what reads as a polished resin die.
        // The floor and walls stay lambert; a shiny floor would fight the
        // matte-table feel.
        material.lightingModel = .blinn
        // Specular deliberately well below white. At full white against
        // the 900-intensity directional key, a facet angled into the light
        // saturates to pure white — and a blown-out face erases the
        // contrast the numerals depend on, which is worse than not being
        // shiny. 0.45 grey gives a clear sheen that tops out around
        // "bright version of the body colour" instead of white.
        material.specular.contents = UIColor(white: 0.45, alpha: 1.0)
        // Lower shininess widens the highlight, spreading the same energy
        // over more of the facet rather than concentrating it into a hot
        // spot that clips.
        material.shininess = 0.35
        material.transparency = 1.0
        material.transparencyMode = .aOne
        // Without this, a mesh with inconsistent or reversed face winding
        // can have its visible surface backface-culled — rendering as a
        // bare outline/silhouette instead of a solid, colored face. This
        // makes both sides of every triangle render regardless of winding,
        // trading a small amount of fill-rate for guaranteed correctness.
        material.isDoubleSided = true
        node.geometry?.materials = [material]
        return true
    }
}
