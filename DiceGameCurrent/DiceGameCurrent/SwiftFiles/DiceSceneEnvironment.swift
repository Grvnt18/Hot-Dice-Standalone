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
    ///
    /// Returns the material so the caller can hold onto it and re-run
    /// `applyTheme` later, when the player picks a different color in
    /// Settings while a game is already on screen.
    @discardableResult
    static func addFloorSurface(
        to rootNode: SCNNode,
        bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        floorY: Float
    ) -> SCNMaterial {
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
        material.diffuse.contents = facetedSurfaceTexture(baseColor: AppTheme.shared.floorBaseColor)
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
        return material
    }

    private static func facetedSurfaceTexture(baseColor: UIColor) -> UIImage {
        LowPolyTextures.facetedSurface(
            baseColor: baseColor.darkened(by: 0.25),
            variation: 0.10,
            columns: 16,
            rows: 16,
            seed: 20260101
        )
    }

    /// "ROLLS" written across the center of the floor in Aguafina Script,
    /// sized to 20% of the playfield's width. Rendered the same way as the
    /// die face labels — UIGraphicsImageRenderer text on a transparent
    /// background, applied to a flat plane — so the floor's own texture
    /// still shows through around the letterforms rather than sitting
    /// behind an opaque patch.
    ///
    /// Text color comes from AppTheme.shared.rollsTextIsDark rather than a
    /// hardcoded white — a bright floor shade (see AppTheme's "Pale
    /// Lavender" swatch) would otherwise wash the script out to near-
    /// illegibility.
    ///
    /// Returns the material so the caller can re-run `applyTheme` when the
    /// floor color changes later.
    @discardableResult
    static func addFloorText(
        to rootNode: SCNNode,
        bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        floorY: Float
    ) -> SCNMaterial {
        let playfieldWidth = bounds.x.upperBound - bounds.x.lowerBound
        let textWidth = playfieldWidth * 0.45 // was 0.3 — enlarged another 50% per request (0.2 -> 0.3 -> 0.45 across two rounds)

        let textImage = renderScriptText("ROLLS", pointSize: 220, isDark: AppTheme.shared.rollsTextIsDark)
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
        return material
    }

    /// Re-renders the floor surface and the "ROLLS" text from AppTheme's
    /// current selection, and assigns the results onto the materials
    /// `addFloorSurface`/`addFloorText` returned when the scene was first
    /// assembled. Call this after the player changes the color in Settings
    /// so an in-progress game updates live instead of only on next launch.
    static func applyTheme(surfaceMaterial: SCNMaterial, textMaterial: SCNMaterial) {
        surfaceMaterial.diffuse.contents = facetedSurfaceTexture(baseColor: AppTheme.shared.floorBaseColor)
        textMaterial.diffuse.contents = renderScriptText("ROLLS", pointSize: 220, isDark: AppTheme.shared.rollsTextIsDark)
    }

    private static func renderScriptText(_ text: String, pointSize: CGFloat, isDark: Bool) -> UIImage {
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
            .foregroundColor: isDark ? UIColor.black : UIColor.white
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

    /// Visible wood frame around the play area — separate from the
    /// invisible physics wall colliders in DicePlayfieldPhysics, which are
    /// kept MUCH taller (effectively infinite containment) than this looks.
    /// Decoupling visual height from physics height on purpose: a wall
    /// tall enough to guarantee no bounce ever clears it would look absurd
    /// (dice are small; the necessary physics margin is large), while a
    /// wall sized to look reasonable wouldn't reliably contain the more
    /// energetic rolls.
    ///
    /// Built as ONE continuous piece of timber wrapping the whole square
    /// playfield, with the playable surface as a square cut out of its
    /// middle — not four independently-textured panels. Each of the 4
    /// segments (left/right run the full height including the corners;
    /// top/bottom fill the remaining gap between them, so nothing overlaps)
    /// gets its UV coordinates computed directly from world position
    /// (worldMappedQuad) rather than SceneKit's per-object default 0-1
    /// mapping — so the SAME point in world space always samples the SAME
    /// texel regardless of which segment happens to cover it there. That's
    /// what makes the grain read as one unbroken board across every seam,
    /// including the four corners, instead of four separately-mapped
    /// panels that merely share a wood tone. A previous version gave each
    /// segment its own default per-object UV (needing per-segment scale/
    /// axis corrections that were hard to get right without a device to
    /// test on) and a different random seed per panel (so even a perfectly
    /// aligned seam would have shown a visible break in the actual grain
    /// pattern) — both are gone here by construction.
    static func addWalls(
        to rootNode: SCNNode,
        bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        floorY: Float,
        visualHeight: Float
    ) {
        let width = bounds.x.upperBound - bounds.x.lowerBound
        // Small cosmetic reach past the nominal bounds, covering any
        // hairline background gap right at the screen edge — much smaller
        // than the old side-wall-only +4.0 fudge, which was compensating
        // for the playfield being a non-square slice of a taller screen
        // before DiceGameScreen started sizing the 3D view to a square.
        let outerMargin: Float = 0.15

        let cutout = (
            x: bounds.x.lowerBound + PlayfieldRim.innerInset ... bounds.x.upperBound - PlayfieldRim.innerInset,
            z: bounds.z.lowerBound + PlayfieldRim.innerInset ... bounds.z.upperBound - PlayfieldRim.innerInset
        )
        let outer = (
            x: bounds.x.lowerBound - outerMargin ... bounds.x.upperBound + outerMargin,
            z: bounds.z.lowerBound - outerMargin ... bounds.z.upperBound + outerMargin
        )

        let y = floorY + visualHeight

        // One shared texture and one shared UV density for every segment —
        // see the type-level doc comment for why that (not per-segment
        // scale corrections) is what actually guarantees a continuous,
        // non-stretched board regardless of which world direction a given
        // segment happens to run in.
        let material = wallMaterial()
        // tileWorldSize matches DiceScoreBar's header background — see
        // PlayfieldRim.woodTileFraction for why both read from one number.
        let tileWorldSize = width * PlayfieldRim.woodTileFraction
        let uPerWorldUnit: Float = 1 / tileWorldSize
        // The source texture is 1024x256 (4:1, wide:tall) — V needs to
        // cycle 4x faster than U so one world-space "tile" maps onto the
        // image without stretching its own aspect ratio.
        let vPerWorldUnit: Float = 4 / tileWorldSize

        // Left and right strips span the FULL outer height, including the
        // corners; top and bottom fill just the remaining inner-width gap
        // between them. Non-overlapping by construction, unlike the old
        // per-box approach's deliberate corner overlap — no seam gap to
        // cover, so nothing needs to reach past a neighbor to hide one.
        addWorldMappedQuad(
            to: rootNode, xRange: outer.x.lowerBound...cutout.x.lowerBound, zRange: outer.z, y: y,
            uPerWorldUnit: uPerWorldUnit, vPerWorldUnit: vPerWorldUnit, material: material
        )
        addWorldMappedQuad(
            to: rootNode, xRange: cutout.x.upperBound...outer.x.upperBound, zRange: outer.z, y: y,
            uPerWorldUnit: uPerWorldUnit, vPerWorldUnit: vPerWorldUnit, material: material
        )
        addWorldMappedQuad(
            to: rootNode, xRange: cutout.x, zRange: outer.z.lowerBound...cutout.z.lowerBound, y: y,
            uPerWorldUnit: uPerWorldUnit, vPerWorldUnit: vPerWorldUnit, material: material
        )
        addWorldMappedQuad(
            to: rootNode, xRange: cutout.x, zRange: cutout.z.upperBound...outer.z.upperBound, y: y,
            uPerWorldUnit: uPerWorldUnit, vPerWorldUnit: vPerWorldUnit, material: material
        )
    }

    private static func wallMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        // Same generator, palette and plank density as the header/footer
        // backdrop (DiceGameShell.HeaderFooterWood) — and the SAME single
        // seed, not a different one per segment, so the frame and the
        // header/footer read as one continuous piece of timber rather than
        // unrelated wood treatments that merely resemble each other.
        // (LowPolyTextures caches by these exact parameters, so this call
        // returns the identical image HeaderFooterWood.image does, without
        // either file needing to see the other's private constant.)
        material.diffuse.contents = LowPolyTextures.woodSurface(
            baseColor: UIColor(hex: "#8B6039"),
            planks: 5,
            shardsPerPlank: 16,
            pixelSize: 1024,
            pixelHeight: 256,
            seed: 77123
        )
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.lightingModel = .lambert
        // Per-vertex UV here is supplied explicitly (see worldMappedQuad)
        // rather than relying on a box's default per-face mapping, so
        // there's no default-winding assumption to get backface-culled by;
        // double-sided is cheap insurance against that regardless.
        material.isDoubleSided = true
        return material
    }

    /// Builds and adds a single flat, upward-facing quad whose texture
    /// coordinates are computed directly from world position — `u =
    /// worldX * uPerWorldUnit`, `v = worldZ * vPerWorldUnit` — rather than
    /// the 0-1 span SceneKit would give a box or plane's own local face.
    /// Any two quads built this way that share a boundary in world space
    /// necessarily agree on the UV at every point along it, since both
    /// compute it from the same shared world coordinates — that's what
    /// makes the wood grain continuous across the seam between them
    /// without needing them to be one literal mesh.
    ///
    /// Only a flat quad, not a full box with real height/thickness: under
    /// the purely top-down orthographic camera (DiceCameraFactory), a
    /// box's vertical side faces are always edge-on and never visible, so
    /// a box's "real" thickness was already contributing nothing to what's
    /// actually on screen — this keeps that same top-down appearance with
    /// far simpler geometry.
    private static func addWorldMappedQuad(
        to rootNode: SCNNode,
        xRange: ClosedRange<Float>,
        zRange: ClosedRange<Float>,
        y: Float,
        uPerWorldUnit: Float,
        vPerWorldUnit: Float,
        material: SCNMaterial
    ) {
        let corners: [(x: Float, z: Float)] = [
            (xRange.lowerBound, zRange.lowerBound),
            (xRange.upperBound, zRange.lowerBound),
            (xRange.upperBound, zRange.upperBound),
            (xRange.lowerBound, zRange.upperBound)
        ]
        let positions = corners.map { SCNVector3($0.x, y, $0.z) }
        let normals = [SCNVector3](repeating: SCNVector3(0, 1, 0), count: 4)
        let uvs = corners.map { CGPoint(x: CGFloat($0.x * uPerWorldUnit), y: CGFloat($0.z * vPerWorldUnit)) }
        // Two triangles, fanned from corner 0 — standard quad triangulation.
        let indices: [Int32] = [0, 1, 2, 0, 2, 3]

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: uvs)
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.castsShadow = false
        rootNode.addChildNode(node)
    }
}
