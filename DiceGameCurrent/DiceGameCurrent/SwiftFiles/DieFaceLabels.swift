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
    ///
    /// d4/d20 weren't chosen by eye like the rest (no device to look at
    /// them on) — derived instead from a ratio measured against the two
    /// shapes above where labelSize IS confirmed-reasonable: labelSize /
    /// (0.85 x face apothem) is ~1.32 for d6 and ~1.41 for d8 (0.85 being
    /// the chamfer inset fraction every mesh here shares, so this compares
    /// against the ACTUAL rendered face size, not the pre-chamfer one).
    /// Using 1.3 (near that range) against d4/d20's own local-unit
    /// apothems (0.816 and 0.577, computed the same way from their
    /// generator's vertex data) gives 0.90 and 0.64. A tetrahedron's 4
    /// faces are proportionally much larger than a cube's 6, so a bigger
    /// label than every other die is the expected direction, not a red
    /// flag — but exactly like d10/d12 above, worth a look once this can
    /// actually be seen on screen.
    private static func labelSize(forSides sides: Int) -> CGFloat {
        switch sides {
        // Unused since the d4 became top-read: addPermanentFaceNumbers
        // routes 4-sided dice to addD4TopReadNumbers, which sizes its
        // three-per-face numerals with d4TopReadLabelSize instead. Kept so
        // the table stays complete for every shape the app can build.
        case 4: return 0.90
        case 6: return 0.65
        case 8: return 0.49
        case 10: return 0.455
        case 12: return 0.39
        case 20: return 0.64
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
    ///
    /// d4/d20 don't have a sourced .dae to measure (see DieFaceNormals'
    /// own note on this) — computed the same way (projecting a face
    /// vertex onto that face's normal) directly from the generator's
    /// plain, pre-chamfer vertex data instead. That's deliberately the
    /// PRE-chamfer shape, not the actual (chamfered) d4.obj/d20.obj being
    /// rendered: chamfering shrinks a face toward its own centroid without
    /// moving that centroid or tilting the face's plane, so the plain and
    /// chamfered versions of the same polyhedron share an identical face-
    /// center distance — measuring the simpler, un-chamfered shape gives
    /// the exact right answer for the chamfered mesh actually on screen.
    /// (Confirms the same is implicitly true of d6/d8/d10/d12's own
    /// values above, which is why measuring from the plain .dae — not the
    /// chamfered .obj that's actually loaded — was already correct.)
    private static func localFaceDistance(forSides sides: Int) -> Float {
        switch sides {
        case 4: return 0.5774
        case 6: return 0.5774
        case 8: return 0.5774
        case 10: return 0.6905
        case 12: return 0.7947
        case 20: return 1.5115
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
        rollsFaceNumber: Int? = nil,
        d4Style: D4LabelStyle = .topRead
    ) {
        // A d4 is not a "number on each face" die — it is read at the
        // apex, with three numerals per face, one beside each corner.
        // Different enough in both layout and meaning to be its own path.
        if sides == 4 {
            addD4TopReadNumbers(to: node, colorway: colorway, style: d4Style)
            return
        }

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
            // On a d10/d12/d20, 6 and 9 are indistinguishable once the die
            // lands at an arbitrary angle — the standard tabletop-dice
            // convention is to underline them so orientation is
            // unambiguous. d4/d6/d8 can't roll a 9 and their 6 (d6 only)
            // is never ambiguous (no 9 exists to confuse it with), so
            // they're left clean.
            let needsUnderline = (sides == 10 || sides == 12 || sides == 20) && (number == 6 || number == 9)
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

    // MARK: - D4 top-read numbering

    /// Which vertex sits opposite each face, by index into
    /// `d4VertexDirections`.
    ///
    /// Exact, not measured: for a tetrahedron centred on the origin, a
    /// face's outward normal is the negation of its opposite vertex's
    /// direction. Checked against `DieFaceNormals.d4` — F0's normal
    /// (+,+,-) is the negation of V3 (-,-,+), and so on down the list.
    private static let d4OppositeVertex: [Int] = [3, 2, 1, 0]

    /// The number printed on each vertex, by `d4VertexDirections` index.
    ///
    /// The choice is arbitrary — all four vertices of a regular
    /// tetrahedron are equivalent under its symmetry group — but it has to
    /// be FIXED, because the numerals drawn on the faces and the value
    /// reported when the die settles both read from this one table.
    private static let d4VertexNumbers: [Int] = [1, 2, 3, 4]

    /// How a numbered d4 is labelled.
    ///
    /// A tetrahedron cannot carry one centred numeral per face and stay
    /// legible: each face is visible in three orientations with a different
    /// corner uppermost each time, so a single numeral would read upright
    /// in at most one of them. Both modes below put numerals at the corners
    /// for exactly that reason; they differ only in which number goes where.
    enum D4LabelStyle {
        /// Each corner carries its own vertex's number, so all three
        /// visible faces show the SAME number at the apex — one value, read
        /// at the point. Free Roll uses this.
        case topRead

        /// Each face carries its own number at all three of its corners, so
        /// the three visible faces show three DIFFERENT numbers around the
        /// apex — one per face, every one upright. Jackpot uses this,
        /// since it reads the three exposed faces rather than a single
        /// value.
        case faceNumbers

        /// No numbers at all: two of the four vertices carry a mark, and
        /// you read the die by whether the point sticking up is marked.
        ///
        /// The traditional Royal UR die. It is the same placement as
        /// `topRead` — a label beside every corner of every face — with a
        /// pip instead of a numeral, and nothing drawn beside the two
        /// unmarked vertices. Because the marked vertices are exactly the
        /// ones `topRead` numbers 1 and 2, a marked-tip die and a numbered
        /// one produce identical results; only the reading is easier.
        case markedTips
    }

    /// Which vertex numbers carry a mark on a `.markedTips` d4.
    ///
    /// Two of four, so the die is an even coin flip. This is the single
    /// source of truth for both the art and the rule that reads it — see
    /// `RoyalUrRules.steps`, which counts marked apexes rather than
    /// testing numbers of its own.
    static let d4MarkedVertexNumbers: Set<Int> = [1, 2]

    /// Whether the apex of a marked-tip d4 resting on `face` is marked —
    /// which is to say, whether that die scored.
    static func d4ApexIsMarked(restingFace face: Int) -> Bool {
        d4MarkedVertexNumbers.contains(d4ApexValue(restingFace: face))
    }

    /// The value shown at the apex of a top-read d4 resting on `face`: the
    /// number on the vertex pointing up, which is the vertex opposite it.
    static func d4ApexValue(restingFace face: Int) -> Int {
        guard d4OppositeVertex.indices.contains(face) else { return 1 }
        return d4VertexNumbers[d4OppositeVertex[face]]
    }

    /// The three face numbers visible on a `.faceNumbers` d4 resting on
    /// `face` — every face except the one against the table.
    ///
    /// Always three distinct values: `{1,2,3,4}` minus the resting face's
    /// number. That is the same distribution the apex reading produces,
    /// which is why Jackpot's odds are identical under either labelling.
    static func d4ExposedFaceNumbers(restingFace face: Int) -> [Int] {
        (1...4).filter { $0 != face + 1 }
    }

    /// Numeral size for the top-read layout. Smaller than
    /// `labelSize(forSides: 4)`'s 0.90 because three now share one face
    /// rather than one having it to itself.
    private static let d4TopReadLabelSize: CGFloat = 0.50

    /// How far out from the face's centre each numeral sits, as a fraction
    /// of the distance from the centre to a corner.
    ///
    /// At 0.62 the numeral's centre lands 1.012 out of a 1.633 face
    /// circumradius and its outer edge reaches 1.287, inside the
    /// chamfered face's ~1.388 limit. Adjacent numerals end up 1.754
    /// apart, more than three times the 0.50 label size, so they cannot
    /// collide.
    private static let d4CornerLabelRadiusFraction: Float = 0.62

    /// Three numerals per face, one beside each corner, each rotated so it
    /// reads upright when that corner is the apex.
    ///
    /// This is what a "top-read" d4 is: the die has no face pointing up
    /// when it lands, so the result is read at the point instead. All
    /// three faces you can see meet at that point and all three carry the
    /// same number beside it.
    private static func addD4TopReadNumbers(
        to node: SCNNode,
        colorway: DieColorway,
        style: D4LabelStyle
    ) {
        let normals = DieFaceNormals.normals(forSides: 4)
        let faceDistance = localFaceDistance(forSides: 4)

        // Distance from a face's centre to its corners, derived from the
        // inradius rather than hardcoded so the two cannot drift apart.
        // For a regular tetrahedron the circumradius is 3x the inradius,
        // so the in-face circumradius is sqrt(R^2 - r^2) = r * sqrt(8).
        let faceCircumradius = faceDistance * (8.0 as Float).squareRoot()
        let cornerOffset = faceCircumradius * d4CornerLabelRadiusFraction
        let liftedDistance = faceDistance * surfaceLiftFactor

        for (faceIndex, normal) in normals.enumerated() {
            let faceNormal = simd_normalize(normal.simd)
            let opposite = d4OppositeVertex[faceIndex]

            for vertexIndex in d4VertexDirections.indices where vertexIndex != opposite {
                // Direction from the face's centre toward this corner,
                // flattened into the face's own plane.
                let vertexDirection = simd_normalize(d4VertexDirections[vertexIndex].simd)
                var towardCorner = vertexDirection
                    - simd_dot(vertexDirection, faceNormal) * faceNormal
                guard simd_length(towardCorner) > 0.001 else { continue }
                towardCorner = simd_normalize(towardCorner)

                // The ONLY difference between the styles. Placement,
                // orientation and count are identical — what lands at this
                // corner is what decides whether the die reads as one
                // value at the point, three around it, or a bare mark.
                let image: UIImage
                switch style {
                case .topRead:
                    image = labelImage(
                        number: d4VertexNumbers[vertexIndex],
                        colorway: colorway,
                        underlined: false
                    )
                case .faceNumbers:
                    image = labelImage(
                        number: faceIndex + 1,
                        colorway: colorway,
                        underlined: false
                    )
                case .markedTips:
                    // An unmarked vertex gets nothing at all, which is what
                    // makes the die readable at a glance: count the pips
                    // around the point that is sticking up.
                    guard d4MarkedVertexNumbers.contains(d4VertexNumbers[vertexIndex]) else {
                        continue
                    }
                    image = pipImage(colorway: colorway)
                }

                let plane = SCNPlane(width: d4TopReadLabelSize, height: d4TopReadLabelSize)

                let material = SCNMaterial()
                material.diffuse.contents = image
                material.isDoubleSided = true
                material.lightingModel = .constant
                material.writesToDepthBuffer = false
                material.readsFromDepthBuffer = true
                plane.materials = [material]

                let labelNode = SCNNode(geometry: plane)
                labelNode.name = "faceLabel"
                labelNode.renderingOrder = 10

                labelNode.position = SCNVector3(
                    faceNormal.x * liftedDistance + towardCorner.x * cornerOffset,
                    faceNormal.y * liftedDistance + towardCorner.y * cornerOffset,
                    faceNormal.z * liftedDistance + towardCorner.z * cornerOffset
                )

                // Explicit basis, same technique the d10 uses: +Z out along
                // the face normal, and +Y — which is the direction the
                // glyph is drawn "up" — pointing at the corner. That is
                // precisely what makes the numeral read the right way up
                // when this corner is the one sticking up.
                let up = towardCorner
                let right = simd_normalize(simd_cross(up, faceNormal))
                labelNode.simdOrientation = simd_quatf(simd_float3x3(right, up, faceNormal))

                node.addChildNode(labelNode)
            }
        }
    }

    // MARK: - D4 corner marks (alternative to numbered faces)

    /// Local-space direction of each of the tetrahedron's 4 original
    /// vertices, in the SAME order used to build d4.obj/d4.dae (see
    /// DieFaceNormals.d4's own comment on that sourcing) — a chamfered
    /// vertex's cap sits exactly along its ORIGINAL (pre-chamfer) vertex
    /// direction, by the same symmetry argument DieFaceNormals relies on
    /// for face normals: cutting a corner off pulls its points toward the
    /// centroid of each adjoining face, but for a REGULAR tetrahedron
    /// those three pulled points stay centered on the original vertex's
    /// own radial line outward from the origin.
    private static let d4VertexDirections: [SCNVector3] = [
        SCNVector3(0.57735, 0.57735, 0.57735),
        SCNVector3(0.57735, -0.57735, -0.57735),
        SCNVector3(-0.57735, 0.57735, -0.57735),
        SCNVector3(-0.57735, -0.57735, 0.57735)
    ]

    /// Distance from center to a vertex cap's own centroid, in the mesh's
    /// local units — computed the same way localFaceDistance is (measured
    /// directly from the generator's vertex/face data), just for a vertex
    /// cap instead of a main face. All 4 are identical for a regular
    /// tetrahedron (verified: every vertex cap sits at exactly the same
    /// distance, as symmetry demands).
    private static let d4VertexLocalDistance: Float = 1.50111

    /// Which 2 of the tetrahedron's 4 vertices (by d4VertexDirections'
    /// index) get a mark. A regular tetrahedron's vertices are all
    /// equivalent under its symmetry group, so which specific 2 are
    /// chosen doesn't matter — any pair gives the same 2-marked/2-blank
    /// split and therefore the same 50/50 odds.
    private static let d4MarkedVertexIndices: Set<Int> = [0, 3]

    /// Size of the corner mark's own square plane, in local units. Much
    /// smaller than a numbered face's label (labelSize(forSides: 4) is
    /// 0.90): the chamfered vertex cap itself is tiny (its own apothem is
    /// roughly 6% of a main face's), so the mark is sized as a fraction of
    /// the numeral label instead of trying to inscribe it in that sliver —
    /// same "fits within the die, legible, not exactly inscribed in its
    /// own facet" latitude labelSize's own doc comment already takes for
    /// the numbered faces. Unverified on an actual screen, same as every
    /// other size in this file that was chosen without a device to look
    /// at it on.
    private static let d4CornerMarkSize: CGFloat = 0.28

    /// Alternative D4 face decoration: a plain filled circle on 2 of the
    /// 4 corners, nothing at all on the other 2 — see
    /// DieMaterial.applyCornerMarkD4's doc comment for why (50/50 marked-
    /// vs-unmarked odds on any roll, instead of reading a 1-4 numeral).
    static func addD4CornerMarks(to node: SCNNode, colorway: DieColorway) {
        let distance = d4VertexLocalDistance * surfaceLiftFactor
        let markImage = cornerMarkImage(colorway: colorway)

        for (index, direction) in d4VertexDirections.enumerated() {
            guard d4MarkedVertexIndices.contains(index) else { continue }

            let plane = SCNPlane(width: d4CornerMarkSize, height: d4CornerMarkSize)
            let material = SCNMaterial()
            material.diffuse.contents = markImage
            material.isDoubleSided = true
            material.lightingModel = .constant
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = true
            plane.materials = [material]

            let markNode = SCNNode(geometry: plane)
            markNode.name = "cornerMark"
            markNode.renderingOrder = 10

            markNode.position = SCNVector3(
                direction.x * distance,
                direction.y * distance,
                direction.z * distance
            )

            let targetNormal = simd_normalize(direction.simd)
            let defaultFacing = simd_float3(0, 0, 1)
            markNode.simdOrientation = simd_quatf(from: defaultFacing, to: targetNormal)

            node.addChildNode(markNode)
        }
    }

    // MARK: Face artwork

    /// The source canvas every face image is drawn at.
    ///
    /// **This number is a memory budget, not only a resolution.** Each face
    /// of each die carries its own image, so a pool costs
    /// `faces x canvas^2 x 4` bytes before SceneKit's own GPU copy. At the
    /// 512 this used, a d20 was 20 MiB on its own and a Free Roll pool of
    /// eight was 160 MiB — which is what made Free Roll die at around eight
    /// dice rather than at its stated cap of twenty.
    ///
    ///     canvas   one d20   eight d20
    ///        512    20 MiB     160 MiB
    ///        256     5 MiB      40 MiB
    ///
    /// 256 is still well above what a face occupies on screen: a die is
    /// roughly 100-200pt on a phone, so the label is oversampled either
    /// way. It was raised from 128 to 512 because Stack Sans ExtraLight's
    /// thin strokes did not survive minification from 128 — 256 keeps
    /// double that detail while cutting the cost fourfold.
    static let labelCanvas: CGFloat = 256

    /// The numeral's point size, as the fraction of the canvas it has
    /// always been (340 of 512).
    private static var glyphPointSize: CGFloat { labelCanvas * 340 / 512 }

    /// Rendered face images, kept because they are rebuilt far more often
    /// than they change.
    ///
    /// `DicePoolLifecycleController.setupPool` tears the pool down and
    /// builds it again, and Free Roll calls that on **every + and - tap**.
    /// Without this, adding the eighth die to a pool re-rendered all eight
    /// dice's faces from scratch — 160 images for a pool of d20s, on the
    /// main thread, per tap.
    ///
    /// Keyed on everything the drawing depends on and nothing else, so two
    /// dice sharing a colourway share their images too.
    private static var imageCache: [String: UIImage] = [:]

    private static func cached(_ key: String,
                               _ build: () -> UIImage) -> UIImage {
        if let hit = imageCache[key] { return hit }
        let image = build()
        imageCache[key] = image
        return image
    }

    /// A single filled circle, centered on a transparent background — the
    /// "marked" corner's decoration. Deliberately not a numeral or any
    /// other symbol: the whole point of this variant is a binary marked/
    /// unmarked read, not a value to identify.
    private static func cornerMarkImage(colorway: DieColorway) -> UIImage {
        cached("mark-\(colorway.numberHex)") { drawCornerMark(colorway: colorway) }
    }

    private static func drawCornerMark(colorway: DieColorway) -> UIImage {
        let size = CGSize(width: labelCanvas, height: labelCanvas)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            // Margin keeps the circle from touching the plane's own edge,
            // same visual role as the padding around a numeral.
            let inset = size.width * 0.18
            let circleRect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            UIColor(hex: colorway.numberHex).setFill()
            UIBezierPath(ovalIn: circleRect).fill()
        }
    }

    /// "ROLLS" in Aguafina Script, sized to fill the same square label
    /// plane a numeral would occupy. Uses aspect-aware scaling rather than
    /// a fixed point size: "ROLLS" is far wider than a single digit, so a
    /// numeral-sized font would overflow the plane's width badly.
    private static func rollsWordmarkImage(colorway: DieColorway) -> UIImage {
        cached("rolls-\(colorway.numberHex)") { drawRollsWordmark(colorway: colorway) }
    }

    private static func drawRollsWordmark(colorway: DieColorway) -> UIImage {
        let size = CGSize(width: labelCanvas, height: labelCanvas)
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
            //
            // Measured as INK on both passes, via AppFonts.inkBounds. The
            // fit used to be computed from `size(withAttributes:)`, the
            // typographic advance, which does not include the S's terminal
            // swash — so "86% of the width" was 86% of a measurement that
            // understated the word, and the tail ran past the margin it
            // was supposed to keep.
            let reference: CGFloat = 200
            let refInk = AppFonts.inkBounds(of: text, font: AppFonts.scriptFont(reference))
            let targetWidth = size.width * 0.86
            let fittedSize = reference * (targetWidth / max(refInk.width, 1))

            let font = AppFonts.scriptFont(fittedSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(hex: colorway.numberHex)
            ]
            // Centred on the ink and drawn at -origin, so what is centred
            // is what you can see rather than what the metrics claim.
            let ink = AppFonts.inkBounds(of: text, font: font)
            text.draw(at: CGPoint(
                x: (size.width - ink.width) / 2 - ink.origin.x,
                y: (size.height - ink.height) / 2 - ink.origin.y
            ), withAttributes: attrs)
        }
    }

    /// A single filled mark, for a `.markedTips` d4.
    ///
    /// Same canvas and same colour as a numeral so a marked die sits in
    /// the set beside the numbered ones — a dot where a digit would be,
    /// not a different kind of die.
    private static func pipImage(colorway: DieColorway) -> UIImage {
        cached("pip-\(colorway.numberHex)") { drawPip(colorway: colorway) }
    }

    private static func drawPip(colorway: DieColorway) -> UIImage {
        let size = CGSize(width: labelCanvas, height: labelCanvas)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            // 0.62 of the canvas, which lands the mark at roughly the
            // visual weight of the numerals it replaces.
            let diameter = size.width * 0.62
            let rect = CGRect(
                x: (size.width - diameter) / 2,
                y: (size.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            UIColor(hex: colorway.numberHex).setFill()
            context.cgContext.fillEllipse(in: rect)
        }
    }

    private static func labelImage(number: Int, colorway: DieColorway,
                                   underlined: Bool) -> UIImage {
        cached("n\(number)-\(colorway.numberHex)-\(underlined)") {
            drawLabel(number: number, colorway: colorway, underlined: underlined)
        }
    }

    private static func drawLabel(number: Int, colorway: DieColorway,
                                  underlined: Bool) -> UIImage {
        // Canvas resolution raised significantly (128 -> 512, now 256 —
        // see labelCanvas for why it came back down) and kept as
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
        let size = CGSize(width: labelCanvas, height: labelCanvas)
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
                // Derived from the canvas rather than restated: the two
                // moved together once already, and a font size left behind
                // by a canvas change is a glyph that no longer fits.
                .font: UIFont(name: AppFonts.stackSansPostScriptName, size: glyphPointSize)
                    ?? UIFont.systemFont(ofSize: glyphPointSize, weight: .bold),
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
