import SceneKit
import UIKit

/// Sets up the non-die parts of the scene: lighting and the visible floor
/// surface. Without this, physically-based die materials render solid
/// black (no light), and the invisible physics floor leaves dice
/// appearing to hover over nothing.
/// How a game's playfield is dressed.
///
/// Every game but one takes `.house`: the faceted surface in whatever
/// colour the player chose in Settings, inside the wooden rim. Rollbots is
/// a neon arena and the timber was never right for it — a dice tray on a
/// table is the wrong object for a duel in the net.
///
/// An opt-in rather than a per-game branch inside the assembler, so adding
/// this costs the other nine games nothing: they pass no style and get
/// exactly what they had.
struct ArenaStyle {

    /// What the floor is made of.
    ///
    /// Faceted for nine games and Rollbots; Baseball Dice draws an actual
    /// pitch instead, because its board IS the game — the runners, the outs
    /// and the line score all live on it.
    enum Surface {
        case faceted
        case baseballField
    }

    var surface: Surface = .faceted

    /// The base colour the faceted floor texture is generated from. Nil
    /// follows the player's table colour, which is what the house style is.
    var surfaceOverride: UIColor?

    /// What the visible rim around the playfield is made of.
    ///
    /// Only the *visible* material. The physics container in
    /// DicePlayfieldPhysics is separate and always built, so `.none`
    /// changes what you see and never what can escape — the two were
    /// decoupled when the walls were written, which is what makes this
    /// safe.
    ///
    /// This was a `Bool` (`showsWoodenRim`) until Rollbots needed a third
    /// state. A bool cannot say "a rim, but not that one", and the
    /// alternative — a second bool beside it — makes "both true" a
    /// representable state that means nothing.
    enum RimMaterial {
        case none
        case wood
        case steel
    }

    var rim: RimMaterial

    static let house = ArenaStyle(surfaceOverride: nil, rim: .wood)

    /// Rollbots: the arena is steel, and so is its rim.
    ///
    /// The rim is NOT timber here on purpose — the wooden tray is the
    /// wrong object for a duel in the net, and that decision is recorded
    /// in three places. This gives the screen the rim every other game
    /// has without reversing it.
    static let steel = ArenaStyle(surfaceOverride: UIColor(hex: "#3A424C"),
                                  rim: .steel)

    /// Baseball Dice: the pitch itself, inside a thin wooden rim.
    static func ballpark() -> ArenaStyle {
        ArenaStyle(surface: .baseballField,
                   surfaceOverride: nil,
                   rim: .wood)
    }

    var surfaceColor: UIColor { surfaceOverride ?? AppTheme.shared.floorBaseColor }
}

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
        // Through the enum: .deferred on device, which is exactly what this
        // line set before, and .forward in the Simulator where the deferred
        // pass asks for a single-channel mask it cannot allocate.
        key.shadowMode = SceneShadows.mode
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
        floorY: Float,
        style: ArenaStyle = .house
    ) -> SCNMaterial {
        let width = bounds.x.upperBound - bounds.x.lowerBound
        let depth = bounds.z.upperBound - bounds.z.lowerBound
        let centerX = (bounds.x.lowerBound + bounds.x.upperBound) / 2
        let centerZ = (bounds.z.lowerBound + bounds.z.upperBound) / 2

        // Single plane — the previous two-layer arrangement (a
        // half-transparent photographic felt texture over a solid green
        // backing) is gone. That existed to tint a photo; the low-poly
        // style wants flat colour instead, which one opaque layer gives
        // directly. Removing the transparency also removes the depth-write
        // and render-order juggling those two layers needed.
        //
        // Painted WIDER than the playfield, by `floorOverscan`. Nothing else
        // grows with it: PlayfieldLayout's bounds, the physics container, the
        // rim quads and the spawn pattern all keep consuming the true bounds,
        // so no die ever notices. The only job of the extra margin is that
        // there is no aspect ratio, rotation or device size at which the
        // camera can see past the floor to the backdrop behind it.
        let plane = SCNPlane(width: CGFloat(width * floorOverscan),
                             height: CGFloat(depth * floorOverscan))
        let material = SCNMaterial()
        applySurface(style: style, to: material)
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0) // lay flat, facing up
        node.position = SCNVector3(centerX, floorY, centerZ)
        node.castsShadow = false

        rootNode.addChildNode(node)
        return material
    }

    /// How much wider than the playfield the floor is painted.
    ///
    /// Small, because it only has to beat rounding and the rim's own cosmetic
    /// bleed, and because everything it covers is off-camera anyway.
    static let floorOverscan: Float = 1.06

    /// Dresses a floor material for a style: the flowing field for the house
    /// and steel arenas, a rendered pitch for the ballpark.
    ///
    /// One function, so building the scene and re-applying the theme cannot
    /// disagree about what a style draws.
    private static func applySurface(style: ArenaStyle, to material: SCNMaterial) {
        switch style.surface {
        case .faceted:
            SmokeFloor.apply(to: material, color: style.surfaceColor)
        case .baseballField:
            // The pitch is a picture of a specific place, not a field of
            // noise, so it stays an image and takes no shader.
            material.shaderModifiers = nil
            material.diffuse.contents = ballparkTexture(for: style)
            material.diffuse.wrapS = .clamp
            material.diffuse.wrapT = .clamp
            material.lightingModel = .lambert
        }
    }

    /// Re-dresses a floor already on screen, when the player changes colour.
    private static func retintSurface(style: ArenaStyle, on material: SCNMaterial) {
        switch style.surface {
        case .faceted:
            SmokeFloor.retint(material, color: style.surfaceColor)
        case .baseballField:
            material.diffuse.contents = ballparkTexture(for: style)
        }
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
        floorY: Float,
        title: String
    ) -> SCNMaterial {
        let playfieldWidth = bounds.x.upperBound - bounds.x.lowerBound
        let textWidth = playfieldWidth * 0.45 // was 0.3 — enlarged another 50% per request (0.2 -> 0.3 -> 0.45 across two rounds)

        let textImage = renderScriptText(title, pointSize: 220, isDark: AppTheme.shared.rollsTextIsDark)
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
    static func applyTheme(
        style: ArenaStyle = .house,
        surfaceMaterial: SCNMaterial,
        textMaterial: SCNMaterial,
        title: String
    ) {
        retintSurface(style: style, on: surfaceMaterial)
        textMaterial.diffuse.contents = renderScriptText(title, pointSize: 220, isDark: AppTheme.shared.rollsTextIsDark)
    }

    /// Rendered floor titles, kept because `applyTheme` rebuilds this on
    /// every colour change and there are only ever a handful of them — one
    /// per game name, times light and dark.
    private static var scriptTextCache: [String: UIImage] = [:]

    private static func renderScriptText(_ text: String, pointSize: CGFloat,
                                         isDark: Bool) -> UIImage {
        let key = "\(text)-\(pointSize)-\(isDark)"
        if let hit = scriptTextCache[key] { return hit }
        let image = drawScriptText(text, pointSize: pointSize, isDark: isDark)
        scriptTextCache[key] = image
        return image
    }

    private static func drawScriptText(_ text: String, pointSize: CGFloat, isDark: Bool) -> UIImage {
        // Falls back to a system font rather than returning a zero-size
        // image if the custom font somehow still isn't available —
        // zero-size directly caused the "gameplay area not rendering" bug
        // (see addFloorText's own comment): it produced an SCNPlane with
        // height=0, degenerate geometry created mid-assembly. A wrong-
        // looking font is a much smaller problem than that.
        let font = AppFonts.scriptFont(pointSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: isDark ? UIColor.black : UIColor.white
        ]
        // Measured as INK, not as advance — this is what was clipping the
        // last letter, and `AppFonts.inkBounds` is now that measurement in
        // one place rather than three. Drawing at -origin is the other
        // half of it: the origin is usually negative, and ignoring it
        // clips the leading stroke instead of the trailing one.
        // canvasBounds, not inkBounds: the union of the ink box and the
        // line box. Sizing from ink alone and then drawing with
        // draw(at:) mixes two coordinate conventions — it held for
        // Aguafina and clipped Lobster's descender off the bottom of the
        // floor wordmark the moment the faces were swapped.
        let ink = AppFonts.canvasBounds(of: text, font: font)
        // A little air beyond the ink, so the wordmark is not flush to the
        // texture's edge where filtering could nibble at it.
        let padding: CGFloat = pointSize * 0.12
        let canvasSize = CGSize(
            width: ceil(ink.width) + padding * 2,
            height: ceil(ink.height) + padding * 2
        )

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { _ in
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: canvasSize))
            text.draw(
                at: CGPoint(x: padding - ink.origin.x, y: padding - ink.origin.y),
                withAttributes: attrs
            )
        }
    }

    /// The floor image a style asks for.
    ///
    /// The ballpark pitch. Portrait, matching the composition the preview
    /// settled. The scoreboard is NOT part of this: it changes during the
    /// game and this texture is built once, so it is its own plane (see
    /// BaseballScoreboard).
    ///
    /// The turf takes the table colour, so the pitch answers the picker like
    /// every other floor. Only the turf — see BaseballField.grass.
    ///
    /// The house and steel arenas have no equivalent, because their floor is
    /// no longer a picture: see `SmokeFloor`.
    private static func ballparkTexture(for style: ArenaStyle) -> UIImage {
        BaseballField.render(size: CGSize(width: 820, height: 1100),
                             turf: style.surfaceColor)
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
        visualHeight: Float,
        material rimMaterial: ArenaStyle.RimMaterial
    ) {
        let width = bounds.x.upperBound - bounds.x.lowerBound
        // Cosmetic reach past the nominal bounds, covering any hairline
        // background gap right at the screen edge. Deliberately NOT one
        // uniform value: the X (left/right) edge needs more of it than Z
        // does. This asymmetry isn't new here — the old per-box wall code
        // had the identical split, widening only the X walls outward
        // ("the camera frames exactly the playfield width, so a rim panel
        // only `thickness` wide left bare background visible beyond it at
        // the left and right edges"), most plausibly because the SwiftUI-
        // driven scene view's width (set indirectly, via a parent's
        // natural sizing) and its height (set explicitly via
        // .frame(height: sceneHeight) in DiceGameScreen) can snap to
        // device pixels independently and land a hair off from a
        // perfectly square 1:1 view even when both are fed the same
        // logical value — a sub-pixel gap that only ever shows up on X.
        // 0.5 is far more than that rounding error could plausibly be,
        // same "generous fixed margin, don't chase the exact sub-pixel
        // source" call the old +4.0 made.
        let outerMarginX: Float = 0.5
        let outerMarginZ: Float = 0.15

        let cutout = (
            x: bounds.x.lowerBound + PlayfieldRim.innerInset ... bounds.x.upperBound - PlayfieldRim.innerInset,
            z: bounds.z.lowerBound + PlayfieldRim.innerInset ... bounds.z.upperBound - PlayfieldRim.innerInset
        )
        let outer = (
            x: bounds.x.lowerBound - outerMarginX ... bounds.x.upperBound + outerMarginX,
            z: bounds.z.lowerBound - outerMarginZ ... bounds.z.upperBound + outerMarginZ
        )

        let y = floorY + visualHeight

        // One shared texture and one shared UV density for every segment —
        // see the type-level doc comment for why that (not per-segment
        // scale corrections) is what actually guarantees a continuous,
        // non-stretched board regardless of which world direction a given
        // segment happens to run in.
        let material = wallMaterial(rimMaterial)
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

    private static func wallMaterial(_ rim: ArenaStyle.RimMaterial) -> SCNMaterial {
        let material = SCNMaterial()
        // Same generator, palette and plank density as the header/footer
        // backdrop (DiceGameShell.HeaderFooterWood / HeaderFooterSteel) —
        // and the SAME single seed, not a different one per segment, so the
        // frame and the header/footer read as one continuous piece of
        // material rather than unrelated treatments that merely resemble
        // each other. (LowPolyTextures caches by these exact parameters —
        // both sides take the defaults, so this call returns the identical
        // image HeaderFooterWood.image / HeaderFooterSteel.image does,
        // without either file needing to see the other's constants.)
        //
        // `.none` never reaches here: addWalls is not called at all for it,
        // so there are no quads to give a material to. It falls to timber
        // rather than crashing because a rim you can see is a better
        // failure than a scene that stops.
        switch rim {
        case .steel: material.diffuse.contents = LowPolyTextures.pixelSteel()
        case .wood, .none: material.diffuse.contents = LowPolyTextures.pixelWood()
        }
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

// MARK: - Antialiasing

/// How much antialiasing every scene in the app uses: none.
///
/// One enum rather than a literal at three call sites, because three things
/// that must agree is how they stop agreeing — the lesson
/// `OverlayChromeButton` taught when the restyle landed on ten screens and
/// read as a bug on the eleventh. `tools_qualcheck.py` asserts no file
/// writes a multisampling literal.
///
/// **Off for the look, and that is the primary reason.** 4x MSAA smooths
/// every die's silhouette, and a smoothed outline is what kept this tray
/// from reading as pixel art even once the faces carried the floor's own
/// Bayer stipple and the turf was posterised: the body was chunky and the
/// EDGE was soft, and the edge is what the eye reads first. Turning it off
/// is what makes a die's outline land on the pixel grid the rest of the
/// surface already sits on.
///
/// So the jaggies are the point. If a future round reads a hard edge as a
/// defect and reaches for `.multisampling4X`, that is the thing to not do —
/// it would undo the dither, the posterisation and this together.
///
/// **And off for the Simulator, which could not have it anyway.** Any
/// multisampling — 2X included, since halving it sets up the same
/// attachment — makes SceneKit ask for a multisampled DEPTH buffer that the
/// Simulator's Metal cannot resolve, and the validation layer aborts the
/// process mid-frame:
///
///     MTLStoreActionMultisampleResolve store action for the depth
///     attachment is not supported by device
///     MTLPixelFormatDepth32Float cannot be a MSAA resolve target
///
/// That abort is why nothing rendered in the Simulator at all: the pass
/// never completed, so there were no dice, the playfield stayed black, and
/// the chrome stopped responding because the app was no longer alive.
///
/// Deliberately NOT written as `#if targetEnvironment(simulator)` returning
/// two different values, which is how this started life. Both environments
/// want the same answer now, and a compile-time branch whose arms are
/// identical reads as though they differ.
enum SceneAntialiasing {

    // Spelled out rather than left as `.none`. Implicit member lookup
    // would resolve it correctly here, but `.none` is also
    // `Optional.none`, and this session has already lost a build to one
    // expression the solver had to work too hard on. Naming the type
    // costs nothing.
    static var mode: SCNAntialiasingMode { SCNAntialiasingMode.none }
}

/// Which shadow technique the key light uses.
///
/// This is the second Simulator render-target gap in the same tray, and
/// the pair of them is the reason this file exists rather than a literal
/// at the call site. `SceneAntialiasing` was a multisampled **depth**
/// attachment the Simulator cannot resolve; this is a single-channel
/// **mask** it cannot allocate:
///
///     MTLDebugValidateMTLPixelFormat: failed assertion
///     'pixelFormat (11) is not a valid MTLPixelFormat.'
///
/// Format 11 is `R8Unorm_sRGB` — one channel, sRGB. A shadow mask is
/// naturally single-channel, because all it stores per pixel is how
/// shadowed that pixel is, and `.deferred` is the mode that renders one:
/// SceneKit resolves shadows in a screen-space pass into a mask and
/// composites it, rather than sampling a shadow map inline.
///
/// `.forward` needs no such target. It samples a conventional depth-only
/// shadow map during the main pass, and a depth map is a format the
/// Simulator has — it is drawing into one already.
///
/// **Why the die materials were the wrong suspect.** The colour-space
/// conversion in the commit before this one is right on its own merits,
/// but it cannot be what fixes this: the assertion also fires in Free
/// Roll, which opens with an **empty pool**. With no dice there are no
/// die materials, so whatever asks for format 11 is present in every
/// tray with or without dice. The key light is, and it is the only thing
/// in the tray that asks for a render target of its own.
///
/// It fits the rest too — every game builds a tray and every tray gets
/// this light, and the hub never asserts because the hub builds no
/// scene at all.
///
/// **Low visual risk, which is worth stating rather than assuming.** The
/// comment at the call site argues for `.deferred` against a *soft area
/// light*, whose broad shadows read as photographic. The light there now
/// is directional with `shadowRadius = 1` — a hard edge under either
/// mode — so forward shadows should be very close to identical, and
/// where they differ, the Simulator is not what anyone ships.
///
/// If the assertion survives this, the next step is `castsShadow = false`
/// in the Simulator: a flat-lit tray that runs beats a correctly lit one
/// that aborts, and shadow quality is exactly the kind of judgement the
/// iPad can make and the Simulator cannot.
///
/// Compile-time, like `SceneAntialiasing`, so the device build is
/// bit-for-bit unchanged and real hardware keeps the deferred pass.
enum SceneShadows {

    static var mode: SCNShadowMode {
        #if targetEnvironment(simulator)
        // Not `.modulated` either — that renders a projected gobo rather
        // than a real shadow, and it would change the look on the one
        // platform we are trying to keep merely runnable.
        return .forward
        #else
        return .deferred
        #endif
    }
}

// MARK: - Render resolution

/// How coarsely every scene in the app is rendered, as drawable pixels per
/// point.
///
/// This is the one thing texture work could never produce. A pattern painted
/// on a surface rotates, stretches and aliases with the geometry; pixel art's
/// defining property is the opposite — a uniform grid in SCREEN space, every
/// pixel the same size whatever the object's orientation or distance. The
/// only way to get that is to render coarse and magnify with no
/// interpolation, which is what this does.
///
/// **1.0, which is gentler than it sounds.** `PlayfieldLayout` maps ten world
/// units across the view's width and `DiceSceneBuilder` normalises every die
/// to 1.0, so a die is always exactly a TENTH of the playfield's width. On an
/// ~820pt playfield that is 82pt, and at one drawable pixel per point a die
/// lands at ~82 pixels across — visibly stepped, and coarse enough that a
/// one-pixel edge reads as a drawn line rather than a hairline. The reference
/// art is nearer 70 pixels across a die; half this would match it exactly and
/// is the knob if this reads too fine.
///
/// **What this does NOT touch**, because it is a property of the scene views
/// alone: every SwiftUI surface stays at full resolution — the score bar, the
/// roll button, the pixel panels, the header and footer timber, the guide
/// bubbles, the hub, Settings, and Royal UR's board, which is a SwiftUI
/// Canvas. World coarse, interface sharp, which is how pixel-art games are
/// normally presented.
///
/// Two costs, measured rather than discovered: Baseball's scoreboard panel is
/// about 40% of the field's width, so it gets ~160 pixels for up to nine
/// inning columns, and the floor wordmark gets ~180 for a whole word. Both
/// are legible but tight, and both are fixable without touching this.
enum SceneRenderScale {

    /// Drawable pixels per point. Below 1.0 is coarser, not finer.
    static let pixelsPerPoint: CGFloat = 1.0

    /// Applies the scale and turns off the interpolation that would undo it.
    ///
    /// Both halves are load-bearing and they only work as a pair. A low
    /// `contentScaleFactor` alone renders coarse and then the layer SMOOTHS
    /// it back up on display, which is blur rather than pixel art — strictly
    /// worse than not doing it. `.nearest` is what keeps the texels hard.
    static func apply(to view: SCNView) {
        view.contentScaleFactor = pixelsPerPoint
        view.layer.magnificationFilter = .nearest
        view.layer.minificationFilter = .nearest
    }
}
