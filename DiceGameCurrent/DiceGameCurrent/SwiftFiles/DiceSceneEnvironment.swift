import SceneKit
import UIKit

/// Sets up the non-die parts of the scene: lighting and the visible floor
/// surface. Without this, physically-based die materials render solid
/// black (no light), and the invisible physics floor leaves dice
/// appearing to hover over nothing.
enum DiceSceneEnvironment {

    /// Adds a soft ambient fill plus one rectangular area light, positioned
    /// above the center of the play area and tilted slightly rather than
    /// pointed perfectly straight down — a dead-center overhead light
    /// flattens the scene, while a slight angle gives dice visible
    /// shading and shadow direction for real depth cues on an otherwise
    /// flat top-down view.
    static func addLighting(
        to rootNode: SCNNode,
        playfieldBounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        floorY: Float,
        lightHeight: Float = 6.0
    ) {
        let ambient = SCNLight()
        ambient.type = .ambient
        // Raised from 250. With a single hard directional key, faces
        // turned away from it would otherwise fall to near-black; a
        // stronger ambient fill keeps unlit facets showing their actual
        // colour, which is characteristic of the flat low-poly look.
        ambient.intensity = 550
        ambient.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)

        // Directional key light, replacing the previous soft area light.
        // Low-poly style depends on adjacent facets catching visibly
        // different amounts of light — that contrast is what makes the
        // faceting readable at all. An area light's soft, diffuse
        // wash flattens exactly that difference, and its deferred soft
        // shadows read as photographic rather than graphic.
        //
        // A directional light also has no falloff, so facets at the edge
        // of the playfield shade the same as ones at the centre, keeping
        // the look even across the whole field.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.color = UIColor.white
        key.castsShadow = true
        key.shadowMode = .deferred
        // Tight, hard-edged shadow rather than the previous radius-4 blur —
        // crisp shadow edges suit the flat-shaded look.
        key.shadowRadius = 1
        key.shadowColor = UIColor(white: 0, alpha: 0.45)
        key.shadowSampleCount = 8

        let keyNode = SCNNode()
        keyNode.light = key
        let centerX = (playfieldBounds.x.lowerBound + playfieldBounds.x.upperBound) / 2
        let centerZ = (playfieldBounds.z.lowerBound + playfieldBounds.z.upperBound) / 2
        // Position is largely cosmetic for a directional light — it has no
        // falloff and lights from its orientation alone — but centring it
        // keeps the shadow frustum over the playfield.
        keyNode.position = SCNVector3(centerX, floorY + lightHeight, centerZ)
        // Angled well off straight-down. With a top-down camera, a light
        // pointing straight down would hit every upward-facing facet
        // identically and erase the shading differences entirely.
        keyNode.eulerAngles = SCNVector3(
            -Float.pi / 3, // ~60° from horizontal, so facets catch light unevenly
            .pi / 6,       // yaw, giving the shading a clear direction
            0
        )
        rootNode.addChildNode(keyNode)
    }

    /// Visible table surface, separate from the invisible physics floor
    /// collider in DicePlayfieldPhysics.
    ///
    /// Stretches the given texture to cover the whole floor as a single
    /// image, rather than tiling it — the source swatches are painterly,
    /// full-scene backgrounds rather than seamless repeatable patterns, so
    /// tiling them reads as an obvious grid rather than one continuous
    /// surface.
    static func addFloorSurface(
        to rootNode: SCNNode,
        bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        floorY: Float
    ) {
        let width = bounds.x.upperBound - bounds.x.lowerBound
        let depth = bounds.z.upperBound - bounds.z.lowerBound
        let centerX = (bounds.x.lowerBound + bounds.x.upperBound) / 2
        let centerZ = (bounds.z.lowerBound + bounds.z.upperBound) / 2

        // Single faceted plane — the previous two-layer arrangement (a
        // half-transparent photographic felt texture over a solid green
        // backing) is gone. That existed to tint a photo; the low-poly
        // style wants flat faceted color instead, which one opaque layer
        // gives directly. Removing the transparency also removes the
        // depth-write and render-order juggling those two layers needed.
        let plane = SCNPlane(width: CGFloat(width), height: CGFloat(depth))
        let material = SCNMaterial()
        material.diffuse.contents = LowPolyTextures.facetedSurface(
            baseColor: UIColor(hex: "#36f422").darkened(by: 0.25),
            variation: 0.10,
            columns: 16,
            rows: 16,
            seed: 20260101
        )
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        // .lambert, not .physicallyBased: pure diffuse shading with no
        // specular highlight. PBR's glossiness is what makes a surface
        // read as "realistic material," which is precisely what the
        // low-poly style is avoiding — flat matte facets are the point.
        material.lightingModel = .lambert
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0) // lay flat, facing up
        node.position = SCNVector3(centerX, floorY, centerZ)
        node.castsShadow = false

        rootNode.addChildNode(node)
    }

    /// "ROLLS" written across the center of the floor in Aguafina Script,
    /// sized to 20% of the playfield's width. Rendered the same way as the
    /// die face labels — UIGraphicsImageRenderer text on a transparent
    /// background, applied to a flat plane — so the floor's own texture
    /// still shows through around the letterforms rather than sitting
    /// behind an opaque patch.
    static func addFloorText(
        to rootNode: SCNNode,
        bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        floorY: Float
    ) {
        let playfieldWidth = bounds.x.upperBound - bounds.x.lowerBound
        let textWidth = playfieldWidth * 0.45 // was 0.3 — enlarged another 50% per request (0.2 -> 0.3 -> 0.45 across two rounds)

        let textImage = renderScriptText("ROLLS", pointSize: 220)
        let aspect = textImage.size.height / max(textImage.size.width, 1)
        let textHeight = textWidth * Float(aspect)

        let plane = SCNPlane(width: CGFloat(textWidth), height: CGFloat(textHeight))
        let material = SCNMaterial()
        material.diffuse.contents = textImage
        material.lightingModel = .constant // unlit, stays legible regardless of scene lighting
        material.isDoubleSided = true
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0) // lay flat, facing up, matching the floor
        node.position = SCNVector3(
            (bounds.x.lowerBound + bounds.x.upperBound) / 2,
            floorY + 0.005, // just above the floor surface, avoids z-fighting
            (bounds.z.lowerBound + bounds.z.upperBound) / 2
        )
        node.castsShadow = false

        rootNode.addChildNode(node)
    }

    private static func renderScriptText(_ text: String, pointSize: CGFloat) -> UIImage {
        // Falls back to a system font rather than returning a zero-size
        // image if the custom font somehow still isn't available —
        // zero-size directly caused the "gameplay area not rendering" bug
        // (see addFloorText's own comment): it produced an SCNPlane with
        // height=0, degenerate geometry created mid-assembly. A wrong-
        // looking font is a much smaller problem than that.
        let font = UIFont(name: AppFonts.aguafinaScriptPostScriptName, size: pointSize)
            ?? UIFont.italicSystemFont(ofSize: pointSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        // Generous padding — script fonts routinely have swashes/flourishes
        // that extend beyond the nominal glyph bounding box, which a tight
        // canvas would clip.
        let padding: CGFloat = pointSize * 0.3
        let canvasSize = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { _ in
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: canvasSize))
            text.draw(at: CGPoint(x: padding, y: padding), withAttributes: attrs)
        }
    }

    /// Visible walls around the play area — separate from the invisible
    /// physics wall colliders in DicePlayfieldPhysics, which are kept
    /// MUCH taller (effectively infinite containment) than these look.
    /// Decoupling visual height from physics height on purpose: a wall
    /// tall enough to guarantee no bounce ever clears it would look
    /// absurd (dice are small; the necessary physics margin is large),
    /// while a wall sized to look reasonable wouldn't reliably contain
    /// the more energetic rolls. This renders a "reasonable" rim — sized
    /// relative to the playfield, like the raised edge of a real dice
    /// tray — while the actual containment boundary stays far taller and
    /// invisible.
    ///
    /// Each of the 4 walls gets a different facet seed, so no two show an
    /// identical pattern while all share one wood tone — same intent the
    /// four sliced photo strips served, without shipping four images.
    static func addWalls(
        to rootNode: SCNNode,
        bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        floorY: Float,
        visualHeight: Float
    ) {
        let width = bounds.x.upperBound - bounds.x.lowerBound
        let depth = bounds.z.upperBound - bounds.z.lowerBound
        let centerX = (bounds.x.lowerBound + bounds.x.upperBound) / 2
        let centerZ = (bounds.z.lowerBound + bounds.z.upperBound) / 2
        // Both the panel thickness and its offset come from PlayfieldRim,
        // which the physics colliders read too — see that type for why
        // these can't be independent numbers.
        let thickness = PlayfieldRim.visualThickness
        let inset = PlayfieldRim.visualCentreOffset

        // The X walls are made MUCH thicker than the rim needs, and all of
        // the extra is added outward, off toward the screen edge. The
        // camera frames exactly the playfield width, so a rim panel only
        // `thickness` wide left bare background visible beyond it at the
        // left and right edges. Widening outward covers that margin while
        // leaving the inner face — and therefore the playable area and the
        // matching physics colliders — exactly where they were.
        let sideThickness: Float = thickness + 4.0
        // Inner face stays at the rim; the added bulk goes outward only.
        let sideCentre = sideThickness / 2 - PlayfieldRim.innerInset

        // Overlap the Z walls past the corners by the side walls' width, so
        // the two runs of planking meet instead of leaving a notch.
        let endWidth = width + sideThickness * 2

        // -X wall, +X wall: run along Z, so the grain tiles along `depth`.
        addOneWall(
            to: rootNode, seed: 101,
            size: SCNVector3(sideThickness, visualHeight, depth), tileLength: depth,
            position: SCNVector3(bounds.x.lowerBound - sideCentre, floorY + visualHeight / 2, centerZ)
        )
        addOneWall(
            to: rootNode, seed: 202,
            size: SCNVector3(sideThickness, visualHeight, depth), tileLength: depth,
            position: SCNVector3(bounds.x.upperBound + sideCentre, floorY + visualHeight / 2, centerZ)
        )
        // -Z wall, +Z wall: run along X, grain tiles across `width`.
        addOneWall(
            to: rootNode, seed: 303,
            size: SCNVector3(endWidth, visualHeight, thickness), tileLength: endWidth,
            position: SCNVector3(centerX, floorY + visualHeight / 2, bounds.z.lowerBound + inset)
        )
        addOneWall(
            to: rootNode, seed: 404,
            size: SCNVector3(endWidth, visualHeight, thickness), tileLength: endWidth,
            position: SCNVector3(centerX, floorY + visualHeight / 2, bounds.z.upperBound - inset)
        )
    }

    private static func addOneWall(
        to rootNode: SCNNode,
        seed: UInt64,
        size: SCNVector3,
        tileLength: Float,
        position: SCNVector3
    ) {
        let box = SCNBox(
            width: CGFloat(size.x),
            height: CGFloat(size.y),
            length: CGFloat(size.z),
            chamferRadius: 0
        )

        let material = SCNMaterial()
        // Same generator, palette and plank density as the header bar
        // (DiceScoreBar.backdrop), so the frame around the playfield and
        // the frame around the score read as one continuous piece of
        // timber rather than two unrelated wood treatments.
        //
        // plankHeightWorld keeps plank size consistent between walls of
        // different lengths: without it, the short Z walls and the long X
        // walls would tile the same image across different distances and
        // end up with visibly different board widths.
        material.diffuse.contents = LowPolyTextures.woodSurface(
            baseColor: UIColor(hex: "#8B6039"),
            planks: 5,
            shardsPerPlank: 16,
            pixelSize: 1024,
            pixelHeight: 256,
            seed: seed
        )
        let tileWorldSize: Float = 4.0
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(max(tileLength / tileWorldSize, 1), 1, 1)
        material.lightingModel = .lambert
        box.materials = [material]

        let node = SCNNode(geometry: box)
        node.position = position
        node.castsShadow = false

        rootNode.addChildNode(node)
    }
}
