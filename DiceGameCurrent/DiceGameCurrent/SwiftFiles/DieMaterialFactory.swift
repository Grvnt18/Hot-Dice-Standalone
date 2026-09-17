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


    static func apply(
        sides: Int,
        colorway: DieColorway,
        to node: SCNNode,
        rollsFaceNumber: Int? = nil,
        grainVariant: Int = 0
    ) {
        guard node.geometry != nil else { return }

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

        DieFaceLabels.addPermanentFaceNumbers(
            to: node,
            sides: sides,
            colorway: colorway,
            rollsFaceNumber: rollsFaceNumber
        )
    }
}
