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

    /// How big a numeral's plane is, DERIVED from the face it has to fit
    /// on and from how many digits it carries.
    ///
    /// Every earlier version of this table was chosen by eye, said so, and
    /// was wrong twice — "a reasonable starting point, not a confirmed-good
    /// size", then +30% on top of that. The faces are in the repository, so
    /// they are measured now. Merging each `.obj`'s coplanar triangles back
    /// into its logical faces and taking the largest circle that fits one:
    ///
    ///     die   numbered faces   inscribed radius (local units)
    ///     d4          4                0.694
    ///     d6          6                0.491
    ///     d8          8                0.347
    ///     d10        10                0.299
    ///     d12        12                0.418
    ///     d20        20                0.491
    ///
    /// A numeral is sized so its own half-diagonal is `faceUse` of that
    /// radius. The numeral is `glyphFill` of its plane and Poppins
    /// SemiBold's digits are about 0.70 em tall and 0.60 em wide, so the
    /// half-diagonal is 0.461 of the plane for ONE digit and 0.695 for two
    /// — which is the whole reason this takes a number and not just a
    /// shape.
    ///
    /// **"10" was the thing holding every other numeral down.** On a d10 it
    /// was already at 91% of the face: the die with the smallest faces and
    /// the only single-digit die that reaches two digits. Sizing per die
    /// meant 1 through 9 were kept small to make room for it. Sized per
    /// NUMBER, a d10's single digits grow 46% and "10" stays where it has
    /// to; a d12's grow 136%.
    ///
    /// d6 is not in here and keeps its own number: it was signed off on
    /// device and nothing about it was asked for.
    private static func labelSize(forSides sides: Int, number: Int) -> CGFloat {
        if sides == 6 { return 0.65 }
        return faceUse(ofDigits: number) * inscribedRadius(forSides: sides)
             / (halfDiagonal(ofDigits: number) * glyphFill(forSides: sides))
    }

    /// How far the INK reaches from its own centre, per em, for a numeral
    /// of one digit or two.
    ///
    /// **Measured off Poppins-SemiBold, not modelled.** These were 0.461
    /// and 0.695, worked out from "digits are about 0.70 em tall and 0.60
    /// wide" — and the model was wrong in both directions. Rendering every
    /// numeral 1 to 20 and taking the ink box says the worst single digit
    /// is 8 at 0.497 and the worst pair is 20 at 0.715: single digits were
    /// being sized against a box 8% smaller than they are, and 20 against
    /// one 3% smaller. The margin `faceUse` is supposed to guarantee was
    /// not the margin they had.
    ///
    /// The two-digit figure is the SQUEEZED one — see
    /// `horizontalSqueeze`, which is what buys the d20 its legibility.
    /// At the 0.80 squeeze the worst pair is still 20, at 0.6139.
    private static func halfDiagonal(ofDigits number: Int) -> CGFloat {
        number >= 10 ? 0.6139 : 0.4974
    }

    /// How much a two-digit numeral is narrowed before it is drawn.
    ///
    /// A numeral is bounded by the half-diagonal of its ink, so a wide
    /// short pair of digits is held down by its WIDTH — "20" is 1.22 em
    /// across against a single digit's 0.64, which is why two-digit faces
    /// came out about two thirds the height of single-digit ones on the
    /// same die.
    ///
    /// Narrowing the pair and spending what that frees on size is what
    /// makes a two-digit face readable. 0.85 bought 18% and was still
    /// short on a d20's 18 and 19 on device; 0.80, with a two-digit
    /// `faceUse` of 1.0, brings it to 33% over where it started — each
    /// digit about 7% narrower than unsqueezed and 25% taller.
    ///
    /// 0.80 is the floor. It is where a normal face stops being narrowed
    /// and starts being condensed, and a condensed digit buys height by
    /// giving up the thing that tells a 3 from an 8. Checked against the alternative first — fitting the box
    /// to the d20's triangular face instead of to the circle inside it
    /// buys nothing, because for a box this wide the two sloping edges
    /// bind within a thousandth of what the circle does.
    private static let twoDigitSqueeze: CGFloat = 0.80

    private static func horizontalSqueeze(forDigits count: Int) -> CGFloat {
        count > 1 ? twoDigitSqueeze : 1
    }

    /// How much of a face's inscribed circle a numeral may reach across.
    ///
    /// Measured to the CORNER of the ink box, which is the emptiest part
    /// of it — a digit is round where its box is square — so a number
    /// below 1.0 is margin on top of margin.
    ///
    /// 0.92 for a single digit was set when the half-diagonals became
    /// measured rather than modelled: against the real ink it leaves a
    /// single digit exactly the size it already was, 0.3% apart, which
    /// made that change honest rather than a numeral grown by stealth.
    /// It stays there because nobody has asked for a bigger 7.
    ///
    /// **1.0 for a pair, and the asymmetry is the point.** A two-digit
    /// box is twice as wide as it is for one digit and no taller, so its
    /// corners are further from any ink than a single digit's are: the
    /// top-left corner of "20" is out beyond the 2's shoulder, where a
    /// single digit's corner is a few hundredths from its own. Spending
    /// that emptiness is what a d20's 18 needs and a d12's 7 does not.
    private static func faceUse(ofDigits number: Int) -> CGFloat {
        number >= 10 ? 1.0 : 0.92
    }

    /// The largest circle that fits on a numbered face, in the mesh's own
    /// local units — the same units `labelSize` and `localFaceDistance`
    /// are in. Measured off the shipped `.obj` files; see labelSize.
    private static func inscribedRadius(forSides sides: Int) -> CGFloat {
        switch sides {
        case 4:  return 0.694
        case 6:  return 0.491
        case 8:  return 0.347
        case 10: return 0.299
        case 12: return 0.418
        case 20: return 0.491
        default: return 0.35
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
        // A d4 is labelled by its own rules — read at the apex with three
        // numerals per face for Free Roll and Royal UR, or one big numeral
        // per face for Jackpot. Different enough in both layout and
        // meaning to be its own path; `d4Style` picks which.
        if sides == 4 {
            addD4TopReadNumbers(to: node, colorway: colorway, style: d4Style)
            return
        }

        let normals = DieFaceNormals.normals(forSides: sides)

        for (index, normal) in normals.enumerated() {
            let number = index + 1
            // Per NUMBER, not per die: "10" needs a wider plane than "7"
            // and was holding every single digit on the die down to its
            // own size. See labelSize.
            let size = labelSize(forSides: sides, number: number)
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
            // On a d10/d12/d20, 6 and 9 are indistinguishable once the die
            // lands at an arbitrary angle — the standard tabletop-dice
            // convention is to underline them so orientation is
            // unambiguous. d4/d6/d8 can't roll a 9 and their 6 (d6 only)
            // is never ambiguous (no 9 exists to confuse it with), so
            // they're left clean.
            let needsUnderline = (sides == 10 || sides == 12 || sides == 20) && (number == 6 || number == 9)
            let isRollsFace = (number == rollsFaceNumber)
            let image = isRollsFace
                ? rollsWordmarkImage()
                : labelImage(number: number, underlined: needsUnderline,
                             sides: sides)
            plane.materials = [artworkMaterial(image: image, colorway: colorway)]

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

            // EVERY shape gets an explicit basis now, not just the d10.
            //
            // `simd_quatf(from:to:)` is the shortest rotation from +Z to
            // the face normal, which pins the plane flat and leaves the
            // ROLL around that normal to fall out of the arithmetic — so
            // each face's numeral sat at whatever angle the normal's
            // direction happened to produce. On a d6 nobody notices,
            // because a cube's normals are axis-aligned and the arbitrary
            // answer is square anyway. On a d12 and a d20 it is visible,
            // and it is most visible on 1 and 7: a digit that is mostly
            // one straight stroke reads as leaning when it leans, where a
            // 3 or an 8 is round enough to look the same either way.
            //
            // The d10 already solved this for itself — see below — and
            // the fix generalises: build a basis with +Z along the face
            // normal and +Y along something CHOSEN, so the roll is a
            // decision rather than a leftover.
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
            } else if sides == 6 {
                // The cube keeps the shortest rotation, and that is not
                // laziness. Its normals are axis-aligned, so the roll
                // that falls out of the arithmetic is already square to
                // the face — the arbitrary answer and the considered one
                // differ by a multiple of 90 degrees, and the arbitrary
                // one is the one that was signed off on device. Changing
                // it would turn d6 numerals a quarter or a half turn for
                // no gain anybody asked for.
                let defaultFacing = simd_float3(0, 0, 1)
                labelNode.simdOrientation = simd_quatf(from: defaultFacing, to: targetNormal)
            } else {
                // Square to the FACE, taken from the mesh rather than
                // from a world axis.
                //
                // Projecting world +Y would square every numeral to the
                // die instead — consistent, and still at an angle to the
                // triangle it is printed on, because a d20's faces are
                // not axis-aligned. It would also have turned a d6's top
                // and bottom numerals upside down, those being the two
                // faces where the projection vanishes.
                //
                // A face's nearest NEIGHBOUR points across the edge they
                // share, so its normal projected into this face is
                // perpendicular to that edge — which is exactly the
                // direction a numeral should stand on. The normals table
                // is already here and already measured off the meshes, so
                // this needs no new data and cannot disagree with the
                // geometry it is aligning to.
                let up = edgeAlignedUp(for: targetNormal, among: normals)
                let right = simd_normalize(simd_cross(up, targetNormal))
                labelNode.simdOrientation = simd_quatf(simd_float3x3(right, up, targetNormal))
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
    /// A tetrahedron shows each face in three orientations, with a
    /// different corner uppermost each time, so a single centred numeral
    /// reads upright in only one of the three. Two of the modes below
    /// answer that by printing at the corners instead; the third takes the
    /// trade the other way, because the game using it reads faces rather
    /// than a value at the point.
    enum D4LabelStyle {
        /// Each corner carries its own vertex's number, so all three
        /// visible faces show the SAME number at the apex — one value, read
        /// at the point. Free Roll uses this.
        case topRead

        /// One big numeral in the middle of each face, the way a
        /// single-number d4 is printed. Jackpot uses this: it reads the
        /// three exposed faces rather than a value at the point, so each
        /// number only has to be unmistakable, not upright — and alone on
        /// its face a numeral is 1.60 across where three sharing one are
        /// 1.00. See `addD4FaceNumbers`.
        ///
        /// This used to be the corner layout with the FACE's number at all
        /// three corners, which kept every numeral upright and paid for it
        /// in size. The legibility went the other way on device.
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

    /// Numeral size for the top-read layout.
    ///
    /// Its own constant rather than derived like the numbered faces: three
    /// numerals share a d4 face, so what bounds one is the gap to its two
    /// neighbours rather than the face's inscribed circle. They grow with
    /// `glyphFill` all the same, which is where this round's legibility
    /// comes from for a d4.
    private static let d4TopReadLabelSize: CGFloat = 1.00

    /// The pip on a marked-tip d4, which keeps the size the corner
    /// numerals used to share.
    ///
    /// Separated when the numerals doubled, and that separation is the
    /// point: Royal UR's dice were signed off on device and nothing about
    /// them was asked for. A mark is not a numeral — it is read by
    /// presence rather than by shape — so it gains nothing from the size
    /// the numbers needed, and the two no longer have to move together.
    private static let d4PipLabelSize: CGFloat = 0.50

    /// How far out from the face's centre each numeral sits, as a fraction
    /// of the distance from the centre to a corner.
    ///
    /// At 0.62 the numeral's centre lands 1.012 out of a 1.633 face
    /// circumradius and its outer edge reaches 1.287, inside the
    /// chamfered face's ~1.388 limit. Adjacent numerals end up 1.754
    /// apart, more than three times the 0.50 label size, so they cannot
    /// collide.
    private static let d4CornerLabelRadiusFraction: Float = 0.62

    /// How far a label may reach from a d4 face's centre before it runs
    /// off the chamfered edge, in local units.
    ///
    /// The measurement the paragraph above was already standing on, now
    /// stated so the placement can be derived from it rather than checked
    /// against it by hand.
    private static let d4FaceReachLimit: Float = 1.388

    /// And how much of that limit a label is allowed to use.
    ///
    /// The chamfer figure is measured off a mesh rather than exact, so the
    /// doubled numerals sit inside it with room to spare instead of
    /// against it: at 0.62 of the circumradius a 1.00 numeral reaches
    /// 1.381 of a 1.388 limit, which is seven thousandths of margin on an
    /// approximate number.
    private static let d4CornerLabelSafety: Float = 0.95

    /// Where a corner label's centre sits, for a label of this size.
    ///
    /// Pulled in from `d4CornerLabelRadiusFraction` only as far as it has
    /// to be: a 0.50 pip keeps the exact placement it had — 1.0125 out,
    /// reaching 1.197 — and a doubled numeral moves in to 0.9498, where it
    /// reaches 1.319. Three of them at 120 degrees are then 1.645 apart
    /// against the 0.738 two of them need, so they still cannot collide.
    private static func d4CornerOffset(labelSize: CGFloat) -> Float {
        let circumradius = localFaceDistance(forSides: 4) * (8.0 as Float).squareRoot()
        let reach = d4LabelHalfDiagonal(labelSize)
        return min(circumradius * d4CornerLabelRadiusFraction,
                   d4FaceReachLimit * d4CornerLabelSafety - reach)
    }

    /// How far the DRAWN numeral reaches from the centre of its plane.
    ///
    /// The plane is bigger than the glyph on it — `glyphFill` of it is
    /// inked, and a single digit's own half-diagonal is 0.461 of that, the
    /// same two numbers `labelSize` divides by. Measuring the plane
    /// instead would price a transparent margin as if it were ink.
    private static func d4LabelHalfDiagonal(_ labelSize: CGFloat) -> Float {
        Float(labelSize * 0.461 * glyphFill(forSides: 4))
    }

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
        // One big numeral per face is its own layout, not a variation on
        // this one. See addD4FaceNumbers.
        if style == .faceNumbers {
            addD4FaceNumbers(to: node, colorway: colorway)
            return
        }

        let normals = DieFaceNormals.normals(forSides: 4)
        let faceDistance = localFaceDistance(forSides: 4)

        // How big a corner label is, and therefore how far out it can sit.
        // A numeral is double what it was; a Royal UR pip is untouched.
        let labelSize = style == .markedTips ? d4PipLabelSize : d4TopReadLabelSize
        let cornerOffset = d4CornerOffset(labelSize: labelSize)
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

                // What lands at this corner: the corner's own number, or a
                // mark on the two vertices that carry one. `.faceNumbers`
                // never reaches here — it returned above, being one
                // numeral in the middle of the face rather than three
                // round the edge of it.
                let image: UIImage
                if style == .markedTips {
                    // An unmarked vertex gets nothing at all, which is what
                    // makes the die readable at a glance: count the pips
                    // around the point that is sticking up.
                    guard d4MarkedVertexNumbers.contains(d4VertexNumbers[vertexIndex]) else {
                        continue
                    }
                    image = pipImage()
                } else {
                    image = labelImage(number: d4VertexNumbers[vertexIndex],
                                       underlined: false, sides: 4)
                }

                let plane = SCNPlane(width: labelSize, height: labelSize)

                plane.materials = [artworkMaterial(image: image,
                                                   colorway: colorway)]

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

    /// One big numeral in the middle of each face: the d4 Jackpot rolls.
    ///
    /// **This is a legibility trade, made deliberately.** The corner
    /// layout above exists because a tetrahedron shows each face in three
    /// orientations — a different corner uppermost each time — so one
    /// numeral per face reads upright in only one of the three. Printing
    /// it three times, once beside each corner, buys that back and costs
    /// size: three numerals sharing a face are bounded by the gap between
    /// each other, not by the face.
    ///
    /// Jackpot does not need what that buys. It reads the three exposed
    /// FACES rather than a single value at the point, so what matters is
    /// that each number is unmistakable, not that it is the right way up —
    /// and 1, 2, 3 and 4 are all legible rotated, which is why the dice
    /// this is modelled on are made at all. The numeral goes from a 1.00
    /// plane crowded against two others to a 1.60 one alone on the face,
    /// sized by `labelSize` off the same measured inscribed radius every
    /// other die uses: 0.59 of reach against the face's 1.388.
    ///
    /// Free Roll keeps `.topRead` and Royal UR `.markedTips`, so this is
    /// Jackpot's d4 and nothing else's.
    private static func addD4FaceNumbers(to node: SCNNode,
                                         colorway: DieColorway) {
        let faceDistance = localFaceDistance(forSides: 4)
        let liftedDistance = faceDistance * surfaceLiftFactor

        for (faceIndex, normal) in DieFaceNormals.normals(forSides: 4).enumerated() {
            let faceNormal = simd_normalize(normal.simd)
            let number = faceIndex + 1
            let size = labelSize(forSides: 4, number: number)

            let plane = SCNPlane(width: size, height: size)
            plane.materials = [artworkMaterial(
                image: labelImage(number: number, underlined: false, sides: 4),
                colorway: colorway)]

            let labelNode = SCNNode(geometry: plane)
            labelNode.name = "faceLabel"
            labelNode.renderingOrder = 10
            labelNode.position = SCNVector3(faceNormal.x * liftedDistance,
                                            faceNormal.y * liftedDistance,
                                            faceNormal.z * liftedDistance)

            // Upright toward ONE of the face's corners — the lowest-index
            // vertex that is not the one opposite this face. Which corner
            // is arbitrary and deterministic both: a numeral alone on a
            // triangular face has three candidate ups and no principled
            // way to choose between them, so the choice is made the same
            // way every time rather than left to the order the normals
            // happen to arrive in.
            let opposite = d4OppositeVertex[faceIndex]
            var up = simd_float3(0, 1, 0)
            for vertexIndex in d4VertexDirections.indices where vertexIndex != opposite {
                let vertexDirection = simd_normalize(d4VertexDirections[vertexIndex].simd)
                let flattened = vertexDirection
                    - simd_dot(vertexDirection, faceNormal) * faceNormal
                guard simd_length(flattened) > 0.001 else { continue }
                up = simd_normalize(flattened)
                break
            }
            let right = simd_normalize(simd_cross(up, faceNormal))
            labelNode.simdOrientation = simd_quatf(simd_float3x3(right, up, faceNormal))

            node.addChildNode(labelNode)
        }
    }

    /// Which way is "up" for a numeral on this face: across its nearest
    /// shared edge.
    ///
    /// The nearest other face is the one on the other side of an edge, so
    /// its normal flattened into this face points at that edge's
    /// midpoint. The numeral stands the other way — AWAY from that edge,
    /// toward the vertex opposite it — which is how a numeral sits on a
    /// real d20: level on a side, point of the triangle above it. Toward
    /// the edge would be equally square and upside down.
    ///
    /// Ties are the rule rather than the exception here: a regular solid
    /// has every neighbour at the same angle, so all three of a d20
    /// triangle's edges are equally near. The first in table order wins,
    /// which makes the choice arbitrary but FIXED — the same face gets
    /// the same answer on every build, and the twenty of them are
    /// consistent with each other because they are all measured the same
    /// way.
    ///
    /// The opposite face is excluded explicitly. It shares no edge, and
    /// its projection is zero-length anyway, but a guard that says why is
    /// worth more than a degenerate case that happens to work.
    private static func edgeAlignedUp(for normal: simd_float3,
                                      among normals: [SCNVector3]) -> simd_float3 {
        var best = simd_float3(0, 0, 0)
        var bestDot: Float = -2

        for candidate in normals {
            let other = simd_normalize(candidate.simd)
            let alignment = simd_dot(other, normal)
            // Itself, or the face directly opposite it.
            guard alignment < 0.999, alignment > -0.999 else { continue }
            let flattened = other - alignment * normal
            guard simd_length(flattened) > 0.001 else { continue }
            if alignment > bestDot {
                bestDot = alignment
                best = -simd_normalize(flattened)
            }
        }

        guard simd_length(best) > 0.001 else {
            // No neighbour at all is not a die, but a NaN orientation
            // would take the whole scene with it.
            let fallback = simd_float3(0, 0, 1)
            let flattened = fallback - simd_dot(fallback, normal) * normal
            return simd_length(flattened) > 0.001
                ? simd_normalize(flattened)
                : simd_float3(0, 1, 0)
        }
        return best
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
    /// smaller than a numbered face's label: the chamfered vertex cap
    /// itself is tiny (its own apothem is
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
        let markImage = cornerMarkImage()

        for (index, direction) in d4VertexDirections.enumerated() {
            guard d4MarkedVertexIndices.contains(index) else { continue }

            let plane = SCNPlane(width: d4CornerMarkSize, height: d4CornerMarkSize)
            plane.materials = [artworkMaterial(image: markImage,
                                               colorway: colorway)]

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
    ///         48    0.2 MiB     1.4 MiB
    ///
    /// **48, and the smallness is the point now rather than a saving.** This
    /// was 256, which is far more than a face occupies on screen — a die is
    /// roughly 100-200pt — so every numeral arrived MINIFIED under the
    /// default linear filter, which is to say smoothly anti-aliased. That was
    /// correct while the dice were shaded resin. It is wrong now that the
    /// body is a three-band cel shade over a Bayer stipple inside a hard
    /// unantialiased silhouette: the numeral was the one perfectly smooth
    /// thing left on the die, and banding the body without this would have
    /// made it stand out more rather than less.
    ///
    /// At 48 a glyph is built of visible texels, magnified with `.nearest`
    /// (see `artworkMaterial`) so they stay hard instead of being
    /// interpolated back into a blur.
    ///
    /// The reason this was 256 no longer holds, and it is worth saying so
    /// rather than leaving a stale justification in place: it was raised from
    /// 128 because **Stack Sans ExtraLight's** thin strokes did not survive
    /// minification. That face left the project in stage C. Poppins is a
    /// much heavier geometric sans and its strokes are what a low canvas
    /// resolves best.
    /// **96 now, and the reasoning above is the one that changed.**
    ///
    /// Everything below this line still holds — a numeral magnified under
    /// a LINEAR filter is a blur, and `.nearest` is what keeps an edge
    /// hard. What 48 added on top of that was visible blocking, and at the
    /// sizes the numerals are now drawn, that blocking is what a two-digit
    /// d20 face could least afford: each digit was about twelve texels
    /// across, which is not enough to tell an 8 from a 9 at a glance.
    ///
    /// 96 doubles the texels in each direction and keeps the hard edges,
    /// because the filter is what makes them hard, not the shortage of
    /// pixels. It is also about the ceiling worth having: a die is roughly
    /// 100-200pt on screen, so at 96 the texture is still being magnified
    /// in the cases that matter, and a texture bigger than the face it
    /// lands on is minified instead — which with `.nearest` and no mips
    /// shimmers as the die tumbles.
    ///
    /// Memory is not the constraint at this size: the worst pool in the
    /// app is Free Roll's twenty dice, which comes to 14 MiB of face
    /// images against a 120 MiB budget — and that is the UNCACHED figure,
    /// with every face its own image.
    static let labelCanvas: CGFloat = 96

    /// The canvas the ROLLS wordmark alone is drawn at.
    ///
    /// Separate from `labelCanvas`, and the one judgement call in this pass.
    /// Lobster is a SCRIPT face: at 48 its thin connecting strokes and the
    /// tail on the S break up into disconnected texels, which reads as a
    /// damaged image rather than as pixel art — the failure the dither's own
    /// comment warns about, where below a certain resolution a thing stops
    /// being the thing.
    ///
    /// 96 is visibly pixelated and still legibly the word. `drawRollsWordmark`
    /// measures and fits its own type, so this is the only number that moves.
    /// Still a twentieth of the old memory, and one die face in one game.
    /// 256, up from 96, and this is the one the request named: ROLLS was
    /// close to unreadable.
    ///
    /// Lobster is a SCRIPT face and its connecting strokes are thin — the
    /// note below already said 48 broke them into disconnected texels, and
    /// 96 turned out to be the same failure one step down rather than a
    /// fix for it. At 256 the thin strokes have four times the texels they
    /// had, which is what a joined script needs to read as joined. It is
    /// one image, drawn once per colourway and cached, so the cost is a
    /// quarter of a megabyte.
    static let wordmarkCanvas: CGFloat = 256

    /// How much of its canvas a numeral fills, per die.
    ///
    /// 340 of 512 — about 0.66 — is what every numeral was drawn at, and
    /// it leaves a third of the canvas empty: the plane is sized to the
    /// face, and then the digit only uses the middle of the plane. Raising
    /// this is free legibility, because it changes nothing about the
    /// plane's footprint on the face.
    ///
    /// 0.80 is the ceiling rather than a taste: a text box is about 1.2
    /// times its point size tall, so 0.80 puts the box at 0.96 of the
    /// canvas and anything higher starts clipping the glyph.
    ///
    /// d6 keeps the old value. It was signed off on device, and widening
    /// its numerals was not asked for.
    private static func glyphFill(forSides sides: Int) -> CGFloat {
        sides == 6 ? 340.0 / 512.0 : 0.80
    }

    private static func glyphPointSize(forSides sides: Int) -> CGFloat {
        labelCanvas * glyphFill(forSides: sides)
    }

    /// Rendered face images, kept because they are rebuilt far more often
    /// than they change.
    ///
    /// `DicePoolLifecycleController.setupPool` tears the pool down and
    /// builds it again, and Free Roll calls that on **every + and - tap**.
    /// Without this, adding the eighth die to a pool re-rendered all eight
    /// dice's faces from scratch — 160 images for a pool of d20s, on the
    /// main thread, per tap.
    ///
    /// **The colour is not part of the key**, because it is not part of the
    /// image: the artwork is drawn in white and tinted through the
    /// material's `multiply` channel (see `artworkMaterial`). That is what
    /// keeps this cache small enough to leave alone.
    ///
    ///     keyed on colour   15 colourways x 20 numbers, + pips,
    ///                       marks and wordmarks       ~94 MiB
    ///     keyed on shape    20 numbers + 2 underlined
    ///                       + pip + mark + wordmark    ~6 MiB
    ///
    /// Six megabytes for the whole app, however many dice in however many
    /// colours across however long a session — where the colour-keyed
    /// version grew all session and never gave anything back.
    ///
    /// `DieMaterialFactory` made exactly this move for the die bodies and
    /// documents why at its `grainTextureCache`: a texture that bakes in a
    /// colour multiplies the cache by the number of colours.
    ///
    /// Bounded anyway, on the principle that an unbounded cache is a leak
    /// with good manners — the cap is far above the ~25 entries this can
    /// now hold, so it never evicts in practice and would only matter if
    /// the colour ever came back into the key.
    private static var imageCache = BoundedImageCache(limit: 64)

    private static func cached(_ key: String,
                               _ build: () -> UIImage) -> UIImage {
        imageCache.image(key, build)
    }

    /// The material every piece of face artwork uses.
    ///
    /// **The colour lives here, not in the image.** The artwork is drawn in
    /// white and tinted through `multiply`, which is what lets one image
    /// serve every colourway — see `imageCache` for the arithmetic. It is
    /// also the same move `DieMaterialFactory` documents making for the die
    /// bodies, for the same reason: a texture that bakes in a colour
    /// multiplies the cache by the number of colours.
    ///
    /// Built as one material and assigned as a whole array rather than
    /// mutated through `firstMaterial?`, which is the fix for an earlier
    /// bug where the diffuse image did not reliably stick.
    private static func artworkMaterial(image: UIImage,
                                        colorway: DieColorway) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = image
        // Nearest, both ways, and this is half of what makes a numeral read
        // as pixel art rather than as a blurry small image. The canvas came
        // down from 256 to 48 (see labelCanvas); magnified back up across a
        // face under the DEFAULT linear filter, SceneKit would interpolate
        // between those texels and hand back a soft smudge — strictly worse
        // than the crisp anti-aliased numeral it replaced. The canvas and the
        // filter only work as a pair.
        //
        // Minification too, not just magnification: a die tumbling away from
        // the camera, or the oversized d20 beside a normal one, samples below
        // 1:1, and a numeral that softens as it recedes would put the smooth
        // gradient back exactly when several dice are on screen together.
        material.diffuse.magnificationFilter = .nearest
        material.diffuse.minificationFilter = .nearest
        // No mipmaps for the same reason the body's dither has none: a mip
        // chain is a pyramid of pre-blurred copies, which is the blur this
        // just removed, arriving by another route.
        material.diffuse.mipFilter = .none
        // White x colour = colour, and the glyph's alpha is untouched, so
        // the transparent surround stays transparent.
        material.multiply.contents = UIColor(hex: colorway.numberHex)
        material.isDoubleSided = true
        // Unlit — keeps the label crisp and legible regardless of scene
        // lighting or angle.
        material.lightingModel = .constant
        // Labels don't write depth: they are thin planes floating a hair
        // off the surface, and letting them occlude subsequent geometry
        // causes visible halos where the body behind them gets
        // depth-rejected. They still READ depth, so a label on the far side
        // of the die is correctly hidden by the body.
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        return material
    }

    /// A single filled circle, centered on a transparent background — the
    /// "marked" corner's decoration. Deliberately not a numeral or any
    /// other symbol: the whole point of this variant is a binary marked/
    /// unmarked read, not a value to identify.
    private static func cornerMarkImage() -> UIImage {
        cached("mark") { drawCornerMark() }
    }

    private static func drawCornerMark() -> UIImage {
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
            UIColor.white.setFill()
            UIBezierPath(ovalIn: circleRect).fill()
        }
    }

    /// "ROLLS" in Aguafina Script, sized to fill the same square label
    /// plane a numeral would occupy. Uses aspect-aware scaling rather than
    /// a fixed point size: "ROLLS" is far wider than a single digit, so a
    /// numeral-sized font would overflow the plane's width badly.
    private static func rollsWordmarkImage() -> UIImage {
        cached("rolls") { drawRollsWordmark() }
    }

    private static func drawRollsWordmark() -> UIImage {
        // wordmarkCanvas, not labelCanvas — see its doc comment. A script
        // face does not survive the resolution the numerals are happiest at.
        let size = CGSize(width: wordmarkCanvas, height: wordmarkCanvas)
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
                .foregroundColor: UIColor.white
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
    private static func pipImage() -> UIImage {
        cached("pip") { drawPip() }
    }

    private static func drawPip() -> UIImage {
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
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: rect)
        }
    }

    /// `sides` only to pick the glyph fill — a d6's numerals are drawn at
    /// the old, smaller fraction and everything else at 0.80. It is in the
    /// cache key for the same reason: two dice wanting different fills of
    /// the same digit are two images, and keying on the number alone would
    /// hand the second one the first one's.
    private static func labelImage(number: Int, underlined: Bool,
                                   sides: Int) -> UIImage {
        let fill = glyphFill(forSides: sides)
        return cached("n\(number)-\(underlined)-\(fill)") {
            drawLabel(number: number, underlined: underlined, sides: sides)
        }
    }

    private static func drawLabel(number: Int, underlined: Bool,
                                  sides: Int) -> UIImage {
        // The history here is worth keeping, because the cause has only
        // now actually been removed.
        //
        // Numerals kept vanishing on d8/d10/d12. The diagnosis was right:
        // Stack Sans Notch was a variable font whose ONLY registered
        // instance was ExtraLight, and those thin strokes had very few
        // pixels to work with once minified onto the smaller label planes
        // — the detail was not there to survive the scale-down. The fix
        // available at the time was resolution, so the canvas went
        // 128 -> 512 -> 256 (see labelCanvas for why it came back down),
        // giving the renderer more pixels to resolve thin strokes before
        // minification. An earlier attempt had swapped in a bold system
        // font, which was rejected for abandoning the typeface to solve a
        // legibility problem.
        //
        // Poppins ends that trade: it ships as separate static weights, so
        // the numerals can simply be SEMIBOLD. The strokes are thick enough
        // to survive minification on their own merits, in the app's actual
        // typeface, which is what both earlier attempts were reaching for.
        // The larger canvas stays — it is cheap, it is cached, and it is
        // now belt-and-braces rather than the load-bearing fix.
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
        return renderer.image { context in
            // Transparent background — only the numeral itself is drawn,
            // so the label reads as printed directly on the body color
            // showing through underneath, not as an opaque patch.
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            let text = "\(number)"
            // Font size derived from the canvas (84 -> 340 when the canvas
            // grew), so the glyph fills a similar proportion of it either
            // way — this was always about resolution, not about making the
            // numeral relatively bigger.
            let attrs: [NSAttributedString.Key: Any] = [
                // Derived from the canvas rather than restated: the two
                // moved together once already, and a font size left behind
                // by a canvas change is a glyph that no longer fits.
                .font: UIFont(name: AppFonts.Weight.semibold.rawValue,
                              size: glyphPointSize(forSides: sides))
                    ?? UIFont.systemFont(ofSize: glyphPointSize(forSides: sides),
                                         weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attrs)
            let origin = CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            )

            // Two digits are drawn NARROWED — see horizontalSqueeze. The
            // scale is about the canvas's own centre line, so a numeral
            // centred before it is centred after it.
            let squeeze = horizontalSqueeze(forDigits: text.count)
            if squeeze < 1 {
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: size.width / 2, y: 0)
                context.cgContext.scaleBy(x: squeeze, y: 1)
                context.cgContext.translateBy(x: -size.width / 2, y: 0)
            }
            text.draw(at: origin, withAttributes: attrs)
            if squeeze < 1 {
                context.cgContext.restoreGState()
            }

            // The bar is drawn OUTSIDE that state, and only ever under a 6
            // or a 9, so it is never narrowed with anything.
            guard underlined else { return }
            // Drawn manually rather than via NSAttributedString's
            // .underlineStyle: that attribute sits tight against the
            // glyph's baseline, which on a die reads as part of the
            // numeral rather than as a separate orientation mark. A
            // deliberately gapped, wider, thicker bar is unmistakably a
            // "which way is up" indicator — matching how real tabletop
            // dice mark their 6 and 9.
            // BIGGER than it was, and snapped to whole texels.
            //
            // It was 0.62 of the numeral's advance by 0.035 of the canvas,
            // which on the 48px canvas is 15.2 x 1.68 — and 1.68 is the
            // problem. The label is drawn at 48px and magnified across a
            // face under a NEAREST filter (see artworkMaterial), so a bar
            // less than two texels tall lands as one lit row and one
            // half-lit one, and the half-lit row is then blown up as its
            // own band of grey. A faint double stripe is exactly what an
            // orientation mark cannot be.
            //
            // 3 texels by 0.80 of the advance: 20 x 3 against a numeral
            // whose own advance is 24.6 and whose ink is 28.7 tall at
            // 38.4pt, measured off Poppins-SemiBold. Rounded, so both
            // edges fall on texel boundaries and the bar magnifies as a
            // solid block.
            //
            // The gap above it is what makes it read as a mark rather than
            // as part of the glyph, so the bar grows DOWNWARD from the
            // same `barY`: the digit's ink ends at 37.6 and the bar still
            // starts at 43.4, leaving the 5.8 that was there before, and
            // its new bottom edge at 46.4 keeps a texel and a half of
            // canvas under it.
            let barWidth = (textSize.width * 0.80).rounded()
            let barHeight = (size.height * 0.0625).rounded()
            let barY = (origin.y + textSize.height * 0.86).rounded()
            let bar = CGRect(
                x: ((size.width - barWidth) / 2).rounded(),
                y: barY,
                width: barWidth,
                height: barHeight
            )
            UIColor.white.setFill()
            UIBezierPath(roundedRect: bar, cornerRadius: barHeight / 2).fill()
        }
    }
}
