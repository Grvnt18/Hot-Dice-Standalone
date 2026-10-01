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

    // MARK: Cel shading

    /// How many flat tone steps a die face is allowed.
    ///
    /// Five flat steps, and the form of a die comes entirely from which step
    /// each facet lands on. There is no texture of any kind on a die body —
    /// see `applyBodyMaterial` — so this is the only thing giving a face
    /// anything to look at.
    ///
    /// **Five is bolder than the three this started at, not a retreat from
    /// it.** Three was the boldest option across the narrow 0.62-1.00 range
    /// it shipped with, where each step was 0.127 of the body colour. Across
    /// 0.08-1.00 five steps are 0.184 apart — bigger steps AND more of them.
    /// It is also about the number of distinct tones in the reference art
    /// this is built from.
    static let celBands: Float = 5

    /// The darkest and brightest a face may be, as a fraction of its own
    /// body colour.
    ///
    /// **This range is set by legibility, and it was measured rather than
    /// chosen.** The first version of this shader quantised a face's ABSOLUTE
    /// luminance to three fixed levels, which is the textbook posterise and
    /// is wrong here for a specific reason: the palette pairs a dark numeral
    /// with a light body and a light numeral with a dark one, and forcing
    /// every body to the same three luminances throws that pairing away.
    /// `tools_dice_preview.check_band_contrast` caught it before the device
    /// did, and the numbers were not close:
    ///
    ///     #1B1B1B on #FCFBF9   16.66:1  ->  1.13:1   (dark band)
    ///     #F5F5F5 on #6E6456    5.32:1  ->  1.35:1   (bright band)
    ///
    /// The numerals would have vanished on roughly a third of the colourways.
    ///
    /// So the bands quantise the SHADE — how far the light moves a face from
    /// its own body colour — and a face is always a shaded version of itself.
    /// At 0.62-1.00 and three bands the factors are 0.683, 0.810 and 0.937,
    /// and the worst pairing in the whole palette is 2.86:1 on `#00ADB4`,
    /// which already sits at 2.52:1 FLAT today. Zero pairings that clear the
    /// 3:1 large-text bar fall below it.
    ///
    /// **0.08, widened hard from 0.62 — and it made legibility BETTER, which
    /// is the opposite of what the first version of this assumed.** That
    /// version protected the numeral on every band, which was answering the
    /// wrong question: the tray camera is straight down orthographic, the key
    /// light is above, and a die snaps to a face on settle, so THE FACE YOU
    /// READ IS ALWAYS THE BRIGHTEST ONE. Side faces sinking to near-black is
    /// not a regression, it is the look.
    ///
    /// Measured on the top band, which is the face that is actually read:
    ///
    ///     range        bands  spread  worst top band
    ///     0.62-1.00      3     1.4x      2.86:1
    ///     0.15-1.00      4     3.5x      3.11:1
    ///     0.08-1.00      5     5.3x      3.03:1   <- ships
    ///     0.05-1.00      6     7.1x      2.96:1
    ///
    /// Widening lowers the top band's own factor (0.937 -> 0.908), and a
    /// slightly darkened body separates BETTER from a light numeral — so the
    /// worst pairing in the palette rises from 2.86:1 to 3.03:1 and clears
    /// the 3:1 large-text bar it currently misses.
    ///
    /// The floor and ceiling are now just the bounds; `celShadeGamma` below
    /// does the shaping.
    static let celShadeFloor: Float = 0.0
    static let celShadeCeiling: Float = 1.0

    /// Curve applied to a band's position before it becomes a shade factor.
    ///
    /// **Measured off the reference art rather than chosen.** Its facets were
    /// sampled from the sprite itself (a 90x90 image at 5px blocks) and, taken
    /// as fractions of its brightest facet, they run:
    ///
    ///     1.00   0.62   0.21   0.05        spread 21.8x
    ///
    /// Those steps are not evenly spaced — they fall away far faster at the
    /// dark end than a linear ramp does, which is why every linear version of
    /// this looked too flat however wide the range was set. Worse, linear
    /// band CENTRES cap the achievable spread at `2n - 1`: five bands can
    /// never exceed 9x, so the reference's 21.8x was out of reach by
    /// construction rather than by tuning.
    ///
    /// A power curve fits it closely. At 1.4 over five bands:
    ///
    ///     factor      0.040  0.185  0.379  0.607  0.863
    ///     of the top   0.05   0.21   0.44   0.70   1.00     spread 21.7x
    ///
    /// The two darkest steps land exactly on the reference's 0.21 and 0.05,
    /// and the spread matches to within a tenth. The extra band simply sits
    /// between its 0.62 and 1.00.
    ///
    /// And it improves legibility a third time, for the same reason widening
    /// did: the top band's factor falls to 0.863, and a slightly darkened body
    /// separates better from a light numeral. The worst pairing in the palette
    /// goes 3.03:1 -> 3.34:1.
    static let celShadeGamma: Float = 1.4

    /// Quantises how strongly the light shades a die body, into
    /// `celBands` flat steps.
    ///
    /// **`.fragment`, not `.surface`, and that is the whole point.** The
    /// floor's modifier is a `.surface` one, which runs BEFORE lighting and
    /// can only set albedo — banding there would be smoothed straight back
    /// out by the lambert term applied after it. `.fragment` receives
    /// `_output.color` once lighting is done, which is the only place a hard
    /// tone step can survive.
    ///
    /// **Nothing rides along in the multiply channel any more**, so what this
    /// measures is pure lighting, which is what it was always meant to be. An
    /// ordered stipple used to sit there and was removed: it had no
    /// counterpart in the reference, and it was the source of the texture
    /// popping in and out as dice tumbled — an 8x8 tile sampled `.nearest`
    /// with no mipmaps aliases badly once a face goes oblique.
    ///
    /// **Hue and saturation are untouched**, because the output is the body
    /// colour scaled, never a replacement. All fifteen colourways stay
    /// exactly as tellable apart — the palette is how a player knows which
    /// die they are looking at, and that is the one property this must not
    /// cost.
    ///
    /// Written in Metal — `float3`, not `vec3`, and nothing from the OpenGL
    /// namespace. A shader modifier is translated into Metal, and one
    /// OpenGL-only identifier takes the entire material down with it, which
    /// is exactly what `u_time` did to the floor. `tools_dice_verify.py` now
    /// scans every shader in the tree for that whole family of spellings.
    ///
    /// `celBase` is a `#pragma arguments` uniform because it genuinely varies
    /// — one value per colourway — where the band count and the range are
    /// interpolated in, being the same for every die. That is the split
    /// SmokeFloor uses too: uniforms for the four tones that change when a
    /// swatch is picked, interpolation for everything fixed.
    static let celModifier: String = """
    #pragma arguments
    float3 celBase;

    #pragma body
    float3 lit = _output.color.rgb;

    // Rec. 601 luminance, for both terms, so the ratio below is a pure
    // measure of lighting and carries no colour of its own.
    float3 celWeights = float3(0.299, 0.587, 0.114);

    // Guarded because a near-black body colour would otherwise divide by
    // zero. Onyx (#14140F) is in the palette, so this is a real case and not
    // a defensive flourish.
    float celBaseLum = max(dot(celBase, celWeights), 0.004);

    // How far the light has moved this fragment from the body's own colour.
    float celShade = dot(lit, celWeights) / celBaseLum;

    float celLo = \(celShadeFloor);
    float celHi = \(celShadeCeiling);
    float celT = clamp((celShade - celLo) / (celHi - celLo), 0.0, 1.0);

    // The same arithmetic SmokeFloor's shader uses to posterise: floor into
    // a band, then clamp so a value of exactly 1.0 lands in the top band
    // rather than one past it.
    float celBand = clamp(floor(celT * \(celBands)), 0.0, \(celBands) - 1.0);

    // The band's CENTRE, not its lower edge, so neither end of the range is
    // ever actually reached. A face driven to its own full brightness is the
    // case that erases a numeral, and one driven to zero is a hole.
    //
    // Raised to celShadeGamma, which is what makes the dark end fall away as
    // steeply as the reference's does. Linear band centres cap the spread at
    // 2n-1 — nine times at five bands — where the reference is 21.8x, so this
    // is not a tuning preference but the only way to reach it at this band
    // count.
    float celStep = pow((celBand + 0.5) / \(celBands), \(celShadeGamma));
    float celFactor = celLo + (celHi - celLo) * celStep;

    _output.color = float4(clamp(celBase * celFactor, 0.0, 1.0),
                           _output.color.a);
    """

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
        }
        // .lambert: flat matte shading with no specular term at all, so a
        // highlight is not merely dialled down but physically impossible.
        //
        // This REVERSES an earlier deliberate choice, and the reasoning is
        // worth keeping rather than quietly deleting. The dice used .blinn
        // with a 0.45 grey specular, chosen so they read as polished resin —
        // a real highlight that topped out near "bright version of the body
        // colour" instead of clipping to white. That was right for a die
        // meant to look like an object.
        //
        // It is wrong for a die meant to look like pixel art, and
        // specifically it is wrong UNDER BANDING: a specular highlight is a
        // smooth gradient, and quantising a smooth gradient turns it into a
        // hard-edged bright blob sitting on the face. That reads as a
        // rendering fault rather than as a style, which is worse than either
        // choice made cleanly. So the sheen goes, and the cel modifier below
        // is what gives a face its form instead.
        //
        // The floor and walls were always lambert, so they are unaffected.
        material.lightingModel = .lambert
        material.transparency = 1.0
        material.transparencyMode = .aOne
        // Without this, a mesh with inconsistent or reversed face winding
        // can have its visible surface backface-culled — rendering as a
        // bare outline/silhouette instead of a solid, colored face. This
        // makes both sides of every triangle render regardless of winding,
        // trading a small amount of fill-rate for guaranteed correctness.
        material.isDoubleSided = true

        // The cel band goes on LAST, over a material that is already
        // complete and already correct. That ordering is load-bearing and it
        // is the idiom SmokeFloor.apply documents: a shader modifier that
        // fails to compile does so asynchronously, on the render thread,
        // rather than throwing — there is nothing to catch and nothing to
        // test for. So the flat body colour is set first and the shader is
        // layered over it. If it compiles it overwrites the lit result; if it
        // does not, the die is a flat-coloured die under ordinary lambert
        // shading — plainer than intended, but correct and readable.
        //
        // The failure mode that ordering removes is a black die, and it is
        // the kind that would not show up here: it would look right on every
        // device whose shader compiles and wrong only on the one where it
        // does not. tools_dice_verify.py asserts the order.
        material.shaderModifiers = [.fragment: celModifier]
        // The body colour the shader shades, as linear components. Read back
        // off the UIColor rather than re-parsed from the hex, so there is one
        // interpretation of a colourway and the shader cannot disagree with
        // material.diffuse about what colour this die is.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: colorway.bodyHex).getRed(&r, green: &g, blue: &b, alpha: &a)
        material.setValue(NSValue(scnVector3: SCNVector3(Float(r), Float(g), Float(b))),
                          forKey: "celBase")

        node.geometry?.materials = [material]
        return true
    }
}
