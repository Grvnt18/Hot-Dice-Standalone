import SceneKit

// MARK: - Mesh loading

/// Loads each die shape's base mesh once (not once per instance) and clones
/// nodes from that cached template — cloning geometry is cheap, re-parsing
/// a .dae file 15 times per pool is not.
enum DieMeshLibrary {

    private static var templateCache: [Int: SCNNode] = [:]

    /// The raw .dae models are NOT uniformly scaled — measured directly
    /// from the meshes: d6 spans ~1.15 world units, d8 ~2.00, d10 ~1.95,
    /// d12 ~1.87. Left uncorrected, the d8/10/12 would render nearly twice
    /// the size of the d6 on screen. These factors normalize every die to
    /// the same reference size (targetSize) so they read as one consistent
    /// die set, matching how a real physical dice set looks.
    private static let targetSize: Float = 1.0

    /// Divisors are each mesh's largest bounding-box dimension, measured
    /// from the actual .obj files. These were re-measured after the meshes
    /// were chamfered: cutting the corners off shrinks the bounding box,
    /// so the old divisors would have rendered every die slightly larger
    /// than intended. d6 is unchanged because a cube's bounding box is
    /// defined by its faces, not its corners, and chamfering leaves the
    /// face planes untouched.
    ///
    /// 4 and 20 aren't used by this game's pool (12 d6 + one each of d8/
    /// d10/d12 — see DiceGameRound.init) — d4.obj/d20.obj were added ahead
    /// of that for the wider project, generated with the same 0.85 chamfer
    /// inset as every other die, and these divisors are already measured
    /// and ready for whenever they're needed.
    private static let sizeNormalizationScale: [Int: Float] = [
        4: targetSize / 1.8000,
        6: targetSize / 1.1547,
        8: targetSize / 1.8000,
        10: targetSize / 1.8369,
        12: targetSize / 1.7909,
        20: targetSize / 3.1743
    ]

    /// Expects each die's mesh available as a bundle resource named "d6",
    /// "d8", "d10", "d12". Tries, in order: .scn (fastest, if you've
    /// converted via Xcode's Editor -> Convert to SceneKit scene file
    /// format on a Mac), .obj (Wavefront — the most reliable choice when
    /// no Mac/Xcode is available, since Swift Playgrounds on iPad has no
    /// build-time conversion step and must parse the mesh at runtime; the
    /// legacy .dae/COLLADA runtime importer was found to throw a generic
    /// parsing error on-device in that environment, while .obj — a much
    /// simpler, actively-supported format — loads reliably), then .dae as
    /// a last resort for setups where the COLLADA importer does work.
    static func templateNode(forSides sides: Int) -> SCNNode? {
        if let cached = templateCache[sides] {
            return independentClone(of: cached)
        }

        let resourceName = "d\(sides)"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "scn")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "obj")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "dae") else {
            print("[DieMeshLibrary] Missing die mesh resource for d\(sides)")
            return nil
        }

        let scene: SCNScene
        do {
            scene = try SCNScene(url: url, options: nil)
        } catch {
            // try? previously swallowed this — surfacing the real error
            // here made the difference between guessing blind and finding
            // the actual root cause (a broken runtime .dae/COLLADA parser
            // in this environment) in one diagnostic pass instead of many.
            print("[DieMeshLibrary] Failed to parse mesh at \(url.path): \(error)")
            return nil
        }

        // The mesh usually sits one level below the scene root rather than
        // on the root node itself, so search for the first node that
        // actually carries geometry.
        let meshNode = scene.rootNode.childNodes.first(where: { $0.geometry != nil })
            ?? (scene.rootNode.geometry != nil ? scene.rootNode : nil)

        guard let meshNode else {
            print("[DieMeshLibrary] No geometry found in d\(sides) scene file.")
            return nil
        }

        let template = meshNode.clone()

        // Explicitly clear any material the importer may have auto-inferred
        // — SceneKit/Model I/O's OBJ loader can auto-bind a same-named or
        // similarly-named image sitting in the same bundle purely by
        // naming convention (e.g. "d8_Numbers.png" next to "d8.obj"), even
        // though our .obj files never declare a material themselves. Left
        // in place, that raw, unrecolored source texture can render
        // instead of (or underneath) DieMaterial.apply's actual output.
        // Starting every template with a genuinely empty materials array
        // makes DieMaterial.apply the only source of truth for appearance.
        template.geometry?.materials = []

        // Bake the size-normalization scale into the template itself so
        // every clone inherits it automatically — no separate step needed
        // at instantiation time, and DiePhysicsFactory can read this same
        // node.scale to keep collision shapes matching the visual size.
        let normalization = sizeNormalizationScale[sides] ?? 1.0
        template.scale = SCNVector3(normalization, normalization, normalization)

        templateCache[sides] = template
        return independentClone(of: template)
    }

    /// SCNNode.clone() is a SHALLOW copy — per Apple's own documentation,
    /// cloned nodes share the SAME geometry (and therefore the same
    /// materials) as the original. Without this extra step, every clone of
    /// a given die shape (all 12 D6s, for example) would share one
    /// SCNMaterial instance — coloring one die would silently recolor
    /// every other die of that shape, since DieMaterial.apply mutates the
    /// material in place. Explicitly copying the geometry after cloning
    /// gives each instance its own independent materials array, which is
    /// exactly the workaround Apple's own SCNNode documentation
    /// recommends for this situation. The underlying vertex data is still
    /// shared (cheap), only the geometry "wrapper" and its materials array
    /// become independent.
    private static func independentClone(of node: SCNNode) -> SCNNode {
        let clone = node.clone()
        if let geometryCopy = clone.geometry?.copy() as? SCNGeometry {
            clone.geometry = geometryCopy
        }
        return clone
    }
}

// MARK: - Pool -> scene bridge

/// Builds the 3D node representation of a DiceGameRound's pool. Each node
/// gets its colored material applied here, at creation time, so nodes are
/// ready to render immediately — no separate colorize pass needed later,
/// and no risk of forgetting to color a die before it's shown.
enum DicePoolSceneBuilder {

    /// Per-die size variation. Every die starts from its shape's
    /// normalized baseline and gets a random multiplier within +/-15%,
    /// EXCEPT one die per round which is instead 50% oversized.
    ///
    /// The oversized die is chosen upfront rather than rolled per-die.
    /// An independent per-die chance (what this originally did) gives a
    /// binomial outcome — some rounds would produce no oversized die at
    /// all, others two or three. Selecting exactly one guarantees the
    /// intended "there's always one big one" read every round.
    private static let sizeVariance: Float = 0.15
    private static let oversizeMultiplier: Float = 1.5

    private static func normalSizeMultiplier() -> Float {
        Float.random(in: (1 - sizeVariance)...(1 + sizeVariance))
    }

    /// Returns one SCNNode per die in the pool, keyed by the die's id so
    /// the roll controller, hit-testing, and selection UI can all look
    /// nodes up by the same id used in the logic layer (DiceGameRound).
    /// Both flags default to true, which is Rolls' behaviour and what every
    /// existing caller gets. Free Roll turns them off: it is a sandbox where
    /// the player chose each die deliberately, so branding one of them
    /// "ROLLS" and inflating another to 1.5x would read as a bug rather
    /// than a flourish.
    static func buildNodes(
        for pool: [Die],
        includeRollsFace: Bool = true,
        includeOversizedDie: Bool = true,
        d4Style: DieFaceLabels.D4LabelStyle = .topRead
    ) -> [UUID: SCNNode] {
        var nodesByID: [UUID: SCNNode] = [:]

        // One random d6 per game gets "ROLLS" in place of its 6.
        let rollsDieID = includeRollsFace
            ? pool.filter { $0.sides == 6 }.randomElement()?.id
            : nil
        // Exactly one die per round is the oversized one. Drawn from the
        // whole pool, not just d6s, so any shape can be the big one.
        let oversizedDieID = includeOversizedDie ? pool.randomElement()?.id : nil

        for die in pool {
            guard let node = DieMeshLibrary.templateNode(forSides: die.sides) else {
                continue
            }

            // Applied BEFORE material and physics, deliberately. Both of
            // those read node.scale: DieFaceLabels divides its face-offset
            // by it (so labels stay flush on a resized die) and
            // DiePhysicsFactory passes it as the collision hull's scale
            // (so the hull matches the visual size). Scaling afterwards
            // would leave labels floating and the hull mismatched.
            let variation = (die.id == oversizedDieID)
                ? oversizeMultiplier
                : normalSizeMultiplier()
            node.scale = SCNVector3(
                node.scale.x * variation,
                node.scale.y * variation,
                node.scale.z * variation
            )

            DieMaterial.apply(
                sides: die.sides,
                colorway: die.colorway,
                to: node,
                rollsFaceNumber: (die.id == rollsDieID) ? 6 : nil,
                grainVariant: Int.random(in: 0..<DieMaterial.grainVariantCount),
                d4Style: d4Style
            )
            DiePhysicsFactory.addPhysicsBody(to: node)

            // Lets hit-testing / debugging map a tapped node straight back
            // to its logical die without a separate lookup table.
            node.name = die.id.uuidString

            nodesByID[die.id] = node
        }

        return nodesByID
    }
}
