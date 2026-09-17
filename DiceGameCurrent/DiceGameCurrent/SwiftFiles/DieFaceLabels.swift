import SceneKit
import UIKit

/// Permanent number labels, one per physical face, placed directly on a
/// die's surface at creation time — not something that only appears after
/// settling. Uses the exact same mechanism the old post-roll badge used (a
/// flat plane with text drawn via UIGraphicsImageRenderer), which was
/// reliable across every die shape, rather than the mesh-UV-texture
/// approach that only ever worked correctly for d8.
///
/// Numbers are assigned by face-normal list order (face 0 shows "1", face
/// 1 shows "2", etc.). Since the badge system was removed, whichever label
/// physically lands face-up after a roll IS the true scored result now
/// (see DiceRollController's FaceSnapping, which reports the landed face's
/// index using this same order) — no longer purely decorative.
enum DieFaceLabels {

    /// d6 and d8 both +30% per explicit aesthetic request (0.50 -> 0.65,
    /// 0.38 -> 0.49). d10/d12 given the same proportional bump — they'd
    /// never actually been visible before this round (their face normals
    /// were wrong; see DieFaceNormals in DiceRollController.swift), so
    /// their previous values were never really evaluated on screen. These
    /// are a reasonable starting point, not a confirmed-good size — worth
    /// a look once you can finally see them.
    private static func labelSize(forSides sides: Int) -> CGFloat {
        switch sides {
        case 6: return 0.65
        case 8: return 0.49
        case 10: return 0.455
        case 12: return 0.39
        default: return 0.40
        }
    }

    /// This was the OTHER, bigger bug ("numbers floating above the die,
    /// not attached") — labels were positioned at a single assumed
    /// distance (0.5 = the die's bounding-box half-extent) for every
    /// shape. That assumption only happens to be exactly correct for a
    /// cube: a cube's face-to-center distance genuinely equals its
    /// bounding half-extent, since cube faces are flat and perpendicular
    /// to the axis with nothing sticking out further in that direction.
    /// For every other shape here, VERTICES stick out further than FACE
    /// CENTERS (true of any polyhedron with flat faces meeting at
    /// pointed corners) — the true face distance is meaningfully
    /// smaller. Computed directly from the actual mesh data (projecting
    /// a face's own vertex onto its normal): d8 ≈ 0.289 (was
    /// positioning 73% too far out), d10 ≈ 0.355 (41% too far), d12 ≈
    /// 0.425 (18% too far). d6's 0.5 was correct all along, which is
    /// exactly why only d6 ever looked right.
    /// Face-center distance in the mesh's OWN local units (before any
    /// normalization or per-die size variation is applied).
    ///
    /// These are deliberately local, not world, values. The previous
    /// version stored normalized world distances and divided by
    /// node.scale to convert — which cancelled out exactly, pinning every
    /// label to a fixed world distance regardless of how big the die
    /// actually was. That was harmless while all dice were the same size,
    /// but broke the moment per-die size randomization landed: dice
    /// scaled UP hid their numbers inside the body, dice scaled DOWN left
    /// them visibly floating. Because the label is a child node, a local
    /// distance scales with its parent automatically, so it stays flush
    /// on the surface at any die size with no compensation math at all.
    ///
    /// Values measured from the .dae meshes by projecting each face's own
    /// vertex onto its normal. Note d6 and d8 share 0.5774 in local units
    /// even though their normalized values differ — they have different
    /// normalization scales.
    private static func localFaceDistance(forSides sides: Int) -> Float {
        switch sides {
        case 6: return 0.5774
        case 8: return 0.5774
        case 10: return 0.6905
        case 12: return 0.7947
        default: return 0.6
        }
    }

    /// Lift off the surface, as a fraction of face distance rather than a
    /// fixed amount — so the gap stays visually proportional on a 1.5x
    /// oversized die instead of shrinking to nothing or gaping open.
    private static let surfaceLiftFactor: Float = 1.03

    /// `rollsFaceNumber`, when set, replaces that face's numeral with the
    /// word "ROLLS" in Aguafina Script — an easter-egg face on one random
    /// d6 per game (chosen in DicePoolSceneBuilder).
    static func addPermanentFaceNumbers(
        to node: SCNNode,
        sides: Int,
        colorway: DieColorway,
        rollsFaceNumber: Int? = nil
    ) {
        let normals = DieFaceNormals.normals(forSides: sides)
        let size = labelSize(forSides: sides)

        for (index, normal) in normals.enumerated() {
            let number = index + 1
            let plane = SCNPlane(width: size, height: size)

            // Building a new SCNMaterial and assigning the whole array
            // explicitly, rather than mutating through firstMaterial?
            // chaining — this is the same fix that resolved an earlier,
            // similar-sounding bug on the die bodies themselves (shared/
            // unreliable material state via firstMaterial? mutation). The
            // visible symptom this round (a plain gray, untextured plane
            // sitting on the die) is consistent with this same class of
            // issue — the geometry/plane itself renders, but the diffuse
            // image assignment doesn't reliably stick.
            let material = SCNMaterial()
            // On a d10/d12, 6 and 9 are indistinguishable once the die
            // lands at an arbitrary angle — the standard tabletop-dice
            // convention is to underline them so orientation is
            // unambiguous. d6/d8 can't roll a 9 and their 6 is never
            // ambiguous (no 9 exists to confuse it with), so they're left
            // clean.
            let needsUnderline = (sides == 10 || sides == 12) && (number == 6 || number == 9)
            let isRollsFace = (number == rollsFaceNumber)
            material.diffuse.contents = isRollsFace
                ? rollsWordmarkImage(colorway: colorway)
                : labelImage(
                    number: number,
                    colorway: colorway,
                    underlined: needsUnderline
                )
            material.isDoubleSided = true
            // Unlit — keeps the label crisp and legible regardless of
            // scene lighting/angle, same reasoning as the old roll badge.
            material.lightingModel = .constant
            // Labels don't write depth: they're thin planes floating a
            // hair off the surface, and letting them occlude subsequent
            // geometry causes visible halos around the numerals where
            // the body behind them gets depth-rejected. They still READ
            // depth, so a label on the far side of the die is correctly
            // hidden by the body.
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = true
            plane.materials = [material]

            let labelNode = SCNNode(geometry: plane)
            labelNode.name = "faceLabel"
            // Draw after the die body so numbers are never partially
            // swallowed by the body surface they sit against. Depth
            // testing stays on (the label is genuinely outside the face,
            // so it passes normally) — this only settles same-depth ties,
            // which is exactly the z-fighting case that can make a numeral
            // flicker or half-disappear as a die tumbles.
            labelNode.renderingOrder = 10

            // Push the plane just outside the surface along this face's
            // own normal, in the mesh's LOCAL units. No node.scale
            // compensation here, deliberately: the label is a child node,
            // so SceneKit already multiplies this by the parent's scale
            // when rendering. Dividing by that scale (what this used to
            // do) cancelled it out and pinned every label to the same
            // world distance regardless of die size — see
            // localFaceDistance's doc comment.
            let distance = localFaceDistance(forSides: sides) * surfaceLiftFactor
            labelNode.position = SCNVector3(
                normal.x * distance,
                normal.y * distance,
                normal.z * distance
            )

            // Orient the plane to lie flat against this face, facing
            // outward along its normal.
            let targetNormal = simd_normalize(normal.simd)

            if sides == 10 {
                // d10 only: control the ROLL around the face normal too,
                // so every number's baseline points toward the die's
                // equator (the horizontal centerline plane). A plain
                // simd_quatf(from:to:) — which is what every other shape
                // uses — produces the shortest rotation from +Z to the
                // normal, leaving the roll arbitrary, so numbers end up
                // at random angles on each face. That reads fine on a
                // cube but looks scattered on a d10's ten angled kites.
                //
                // Build an explicit basis instead: local +Z -> face
                // normal, local +Y -> "up the face, away from the
                // equator." Since the plane's texture is drawn with its
                // own +Y as up, pointing that away from the equator puts
                // the bottom of the glyph toward the equator.
                let awayFromEquator = simd_float3(0, targetNormal.y >= 0 ? 1 : -1, 0)
                // Project that onto the face plane, so "up" actually lies
                // in the face rather than poking through it.
                var up = awayFromEquator - simd_dot(awayFromEquator, targetNormal) * targetNormal
                if simd_length(up) < 0.001 {
                    // Degenerate: face points straight up/down, so there's
                    // no meaningful equator direction. No d10 face
                    // actually does this (max |y| is ~0.74), but guard
                    // rather than emit a NaN orientation if the mesh ever
                    // changes.
                    up = simd_float3(0, 0, 1) - simd_dot(simd_float3(0, 0, 1), targetNormal) * targetNormal
                }
                up = simd_normalize(up)
                let right = simd_normalize(simd_cross(up, targetNormal))
                labelNode.simdOrientation = simd_quatf(simd_float3x3(right, up, targetNormal))
            } else {
                // A plane's default facing direction is +Z, so rotate
                // from +Z to the target normal.
                let defaultFacing = simd_float3(0, 0, 1)
                labelNode.simdOrientation = simd_quatf(from: defaultFacing, to: targetNormal)
            }

            node.addChildNode(labelNode)
        }
    }

    /// "ROLLS" in Aguafina Script, sized to fill the same square label
    /// plane a numeral would occupy. Uses aspect-aware scaling rather than
    /// a fixed point size: "ROLLS" is far wider than a single digit, so a
    /// numeral-sized font would overflow the plane's width badly.
    private static func rollsWordmarkImage(colorway: DieColorway) -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { _ in
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            let text = "ROLLS"
            // Measure at a reference size, then scale the font so the word
            // spans ~86% of the plane width — keeps it large but clear of
            // the face edges.
            let reference: CGFloat = 200
            guard let refFont = UIFont(name: AppFonts.aguafinaScriptPostScriptName, size: reference) else {
                return
            }
            let refWidth = text.size(withAttributes: [.font: refFont]).width
            let targetWidth = size.width * 0.86
            let fittedSize = reference * (targetWidth / max(refWidth, 1))

            guard let font = UIFont(name: AppFonts.aguafinaScriptPostScriptName, size: fittedSize) else {
                return
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(hex: colorway.numberHex)
            ]
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            ), withAttributes: attrs)
        }
    }

    private static func labelImage(number: Int, colorway: DieColorway, underlined: Bool) -> UIImage {
        // Canvas resolution raised significantly (128 -> 512) and kept as
        // Stack Sans per your correction — my previous switch to a bold
        // system font was the wrong fix for the wrong reason. The size
        // request was aesthetic, not a workaround, and abandoning the
        // font wasn't the right way to solve legibility either. The real
        // issue: Stack Sans Notch's only registered instance is
        // ExtraLight (thin strokes), and at a 128px source canvas, those
        // thin strokes had very few pixels to work with once minified
        // onto d8/d10/d12's smaller label planes — the detail simply
        // wasn't there to survive the scale-down. A 4x larger source
        // canvas gives the renderer far more pixels to resolve those thin
        // strokes clearly before any minification happens, which should
        // let them survive shrinking onto even d12's small labels while
        // staying genuinely Stack Sans throughout.
        let size = CGSize(width: 512, height: 512)
        // Explicit format with opaque = false — UIGraphicsImageRenderer's
        // default format can be opaque depending on context, which would
        // silently discard the transparent background this relies on
        // (UIColor.clear rendering as solid black/undefined instead of
        // see-through). Being explicit here removes that ambiguity
        // entirely rather than relying on whatever the default happens to
        // be in this environment.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            // Transparent background — only the numeral itself is drawn,
            // so the label reads as printed directly on the body color
            // showing through underneath, not as an opaque patch.
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            let text = "\(number)"
            // Back to Stack Sans, per your correction. Font size scaled
            // up to match the 4x larger canvas (84 -> 340), so the glyph
            // still fills a similar proportion of the canvas as before —
            // this is about resolution/fidelity, not making the glyph
            // relatively bigger within its own canvas.
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: AppFonts.stackSansPostScriptName, size: 340) ?? UIFont.systemFont(ofSize: 340, weight: .bold),
                .foregroundColor: UIColor(hex: colorway.numberHex)
            ]
            let textSize = text.size(withAttributes: attrs)
            let origin = CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            )
            text.draw(at: origin, withAttributes: attrs)

            guard underlined else { return }
            // Drawn manually rather than via NSAttributedString's
            // .underlineStyle: that attribute sits tight against the
            // glyph's baseline, which on a die reads as part of the
            // numeral rather than as a separate orientation mark. A
            // deliberately gapped, wider, thicker bar is unmistakably a
            // "which way is up" indicator — matching how real tabletop
            // dice mark their 6 and 9.
            let barWidth = textSize.width * 0.62
            let barHeight = size.height * 0.035
            let barY = origin.y + textSize.height * 0.86
            let bar = CGRect(
                x: (size.width - barWidth) / 2,
                y: barY,
                width: barWidth,
                height: barHeight
            )
            UIColor(hex: colorway.numberHex).setFill()
            UIBezierPath(roundedRect: bar, cornerRadius: barHeight / 2).fill()
        }
    }
}
