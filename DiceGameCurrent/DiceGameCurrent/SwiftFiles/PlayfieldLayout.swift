import Foundation

/// Computes playfield world bounds and the matching camera orthographicScale
/// directly from the screen's aspect ratio — no SCNView/camera needs to
/// exist yet, which resolves a circular dependency in the original design:
/// DiceCameraFactory needed bounds to frame itself, but the old
/// PlayfieldBoundsCalculator needed an already-framed camera to unproject
/// through. Since we committed to an orthographic top-down camera, that
/// unprojection approach was solving a harder problem than necessary —
/// orthographic bounds have a simple closed-form relationship to
/// orthographicScale and aspect ratio (visible height = 2 x
/// orthographicScale, width = height x aspect), so we can compute
/// everything up front instead.
///
/// Width, not depth, is fixed as the reference dimension: phone screens
/// vary somewhat in exact aspect ratio, but portrait width is the more
/// consistently constrained dimension, and fixing it guarantees the
/// dice grid's column spacing is always safe regardless of device —
/// depth (rows) just gets more or less room on taller/shorter phones,
/// which DiceSpawnPattern already adapts to.
enum PlayfieldLayout {

    struct Result {
        let bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>)
        let orthographicScale: Double
    }

    /// targetWorldWidth is a design choice, not derived from the device.
    /// Increased from 6.0 to 10.0 as part of pushing for more visibly
    /// energetic rolls without raising raw impulse further — the actual
    /// tunneling-safety math showed current impulse values are already
    /// 17-30x past a safe margin for the floor collider, so more force
    /// risks dice glitching through geometry rather than looking more
    /// lively. A bigger playfield gives the same velocity more real
    /// distance to travel and more room to collide with other dice before
    /// hitting a wall, which reads as "more energetic" without touching
    /// the part of the system that's already at its practical ceiling.
    static func compute(
        screenAspectRatio: Float, // view width / view height
        targetWorldWidth: Float = 10.0
    ) -> Result {
        let width = targetWorldWidth
        let depth = width / screenAspectRatio

        let bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>) = (
            x: -width / 2 ... width / 2,
            z: -depth / 2 ... depth / 2
        )

        // Inverse of: width = (2 x orthographicScale) x aspect
        let orthographicScale = Double(width / (2 * screenAspectRatio))

        return Result(bounds: bounds, orthographicScale: orthographicScale)
    }

    // MARK: Staying right when the window changes size

    /// **The arena depends on the view's SHAPE, never on its size.** Read
    /// `compute` above: `targetWorldWidth` is a design constant, and both
    /// the bounds and the camera scale come from it and the aspect ratio
    /// alone. Nothing in there is in points.
    ///
    /// That is what makes the next part small. `DiceSceneAssembler`
    /// derives the aspect once, at assembly, and `assembleIfReady` is
    /// guarded so a later layout pass does nothing — so a view that
    /// changes shape after assembly keeps walls and a camera built for the
    /// shape it used to be. A view that merely changes SIZE is already
    /// correct and needs nothing.
    ///
    /// Until a foldable existed that was close to unreachable: the app is
    /// portrait-only, so the shape only moved on a Split View drag. The
    /// iPhone Duo changes it by folding. Measured across every size in
    /// `tools_bandlayout_verify.py`, including both of the Duo's:
    ///
    ///   | header fraction        | folded | open  | drift |
    ///   |------------------------|--------|-------|-------|
    ///   | Boneheads 0.14         | 1.000  | 1.000 | 0     |
    ///   | Rolls, Royal UR 0.15   | 1.000  | 1.000 | 0     |
    ///   | the five at 0.17       | 1.000  | 1.000 | 0     |
    ///   | Free Roll 0.30         | 1.228  | 1.186 | 0.042 |
    ///
    /// So ten of the eleven cannot drift at all: their playfield is square
    /// at both of the Duo's sizes, and a square is a square at any size.
    /// Free Roll's header takes 0.30 against everyone else's 0.14 to 0.17,
    /// which is what pushes its playfield off square — and it moves on an
    /// iPad today too, by 0.066 across a Split View drag from 320 to 744.
    static let aspectRebuildThreshold: Float = 0.02

    static func aspect(of size: CGSize) -> Float {
        Float(size.width / max(size.height, 1))
    }

    /// Whether the arena was built for a materially different shape.
    ///
    /// The threshold is doing real work rather than padding a comparison.
    /// Re-assembly throws the dice away and re-deals them, which is
    /// acceptable in a sandbox and NOT acceptable part way through a
    /// scored round — so this has to be a test the games that would be
    /// hurt by it cannot pass. At 0.02 the only screen that ever reaches
    /// it is Free Roll, which has no score and no turn;
    /// `tools_bandlayout_verify.py` asserts exactly that, at every size,
    /// so the day somebody moves a header fraction the check says which
    /// game just became resettable rather than a player finding out.
    ///
    /// Nil means nothing has been assembled yet, which is not a rebuild.
    static func needsRebuild(assembled: Float?, now: Float) -> Bool {
        guard let assembled else { return false }
        return abs(now - assembled) > aspectRebuildThreshold
    }
}

/// Single definition of the playfield rim, shared by the visible walls
/// (DiceSceneEnvironment.addWalls) and the physics colliders
/// (DicePlayfieldPhysics.makeContainer).
///
/// These were previously two independent sets of numbers, and they drifted:
/// widening the visible rim inward moved the wood 0.24 units into the play
/// area while the colliders stayed on the original bounds, so dice bounced
/// off thin air and visually sank into the frame. Deriving both from the
/// values here makes that class of mismatch impossible.
enum PlayfieldRim {

    /// Thickness of the visible wooden frame.
    static let visualThickness: Float = 0.30

    /// How far the frame's outer edge sits OUTSIDE the nominal bounds.
    /// Small, so the rim reads as sitting on the table's edge.
    static let outwardOverhang: Float = 0.06

    /// How far the frame's inner face intrudes INTO the nominal bounds.
    /// This is the number both the walls and the colliders align to — it's
    /// the real edge of the playable surface.
    static var innerInset: Float { visualThickness - outwardOverhang }

    /// Centre offset for a collider, measured OUTWARD from the nominal
    /// bound, such that its inner face lands exactly on `innerInset`.
    /// Colliders stay thick (see DicePlayfieldPhysics) for tunneling
    /// safety, so this offset keeps that thickness entirely behind the
    /// visible surface.
    static func colliderCentreOffset(thickness: Float) -> Float {
        thickness / 2 - innerInset
    }

    /// Fraction of the playfield's world width that one copy of the wood
    /// texture spans when tiled across the walls (DiceSceneEnvironment.
    /// addWalls, via its world-position-derived UV). DiceScoreBar's header
    /// background is painted with the same fraction of its own on-screen
    /// width, rather than stretching one copy across the whole bar —
    /// that's what keeps the plank pitch continuous across the seam
    /// between the header and the walls instead of jumping to a different
    /// scale right where they meet.
    /// Raised from 0.4 with the move to three boards. At the old value five
    /// planks landed at about 2% of the screen each, which reads as veneer;
    /// this puts a board at a size you could believe someone planed.
    static let woodTileFraction: Float = 0.75
}

/// Vertical containment shared between the camera (DiceCameraFactory), the
/// invisible ceiling collider (DicePlayfieldPhysics), and
/// DiceRollController's containment safety net — all three need to agree on
/// how high the play area extends.
///
/// Without any ceiling at all, nothing stops a die from climbing arbitrarily
/// high above the floor — the side walls are tall enough to block any
/// sideways escape at any height, so an unbounded top never let a die leave
/// the playfield horizontally, but it left one real way out: gaining enough
/// height (e.g. an energetic multi-die collision on top of an already-
/// energetic bounce) closes the distance to the top-down camera itself. The
/// camera's zNear plane clips anything closer than 0.1 units away, so a die
/// climbing past roughly (cameraHeight - 0.1) simply vanishes — which reads
/// exactly like "the die left the rolling area through the ceiling."
///
/// ceilingHeight is set far below that camera-clipping threshold, though —
/// low enough to double as an anti-stacking constraint, by request, while
/// staying clear of two other numbers it has to respect:
///
/// - The STACKING threshold, i.e. the lowest a stacked die's center could
///   possibly be. The floor collider is a 0.7-thick box CENTERED on
///   floorY (see DicePlayfieldPhysics.makeContainer), so a resting die's
///   center actually sits at floorY + 0.35 (the floor's own half-
///   thickness) + its own half-height, not floorY + half-height alone.
///   With the smallest dice at ~0.5 half-height (targetSize is normalized
///   to ~1 world unit per DieMeshLibrary) resting at ~0.85, a second one
///   stacked on top needs its own center at roughly 0.85 + 0.5 (the
///   bottom die's remaining half) + 0.5 (its own half) ≈ 1.85. Below
///   that, in TERMS OF WHAT THE CEILING BLOCKS: a die's center can only
///   rise to (ceilingHeight - 0.35, the ceiling's own half-thickness -
///   its own half-height), so for the smallest, easiest-to-lift dice
///   (~0.5 half-height) to never reach 1.85, ceilingHeight must stay
///   below roughly 2.7.
/// - Spawn clearance: DicePoolLifecycleController positions the initial
///   15-die pyramid with its highest slot at (baseHeight + 2 stagger
///   tiers), and the pool ALWAYS includes one 1.5x-oversized die
///   (DicePoolSceneBuilder.oversizeMultiplier) with a ~0.75 half-height —
///   that combination has to fit entirely below the ceiling's own
///   underside, or the very first frame after spawn overlaps a static
///   collider and the physics solver violently ejects the die. With
///   DiceSpawnPattern's current baseHeight (1.0) and stagger (0.05/tier),
///   that highest point is ~1.85, so ceilingHeight needs to clear
///   1.85 + 0.35 (its own half-thickness) with a real margin — comfortably
///   satisfied above roughly 2.4.
///
/// 2.5 sits inside that (2.4, 2.7) window with margin on both sides. It's
/// not a mathematically airtight guarantee against the most idealized
/// possible stack (that would need a tighter ceiling than spawn clearance
/// allows without also touching DiceSpawnPattern's own numbers further),
/// but it cuts the available vertical runway by 4x versus the previous
/// value (10) — a huge reduction in how much energy/precision a stack
/// would need — while DiceRollController's existing reactive anti-stacking
/// (attemptRollOff during a roll, and resolveStacking's final geometric
/// separation pass, whose own doc comment already guarantees "a die
/// physically cannot be above another one" once a roll settles) remains
/// the actual, absolute guarantee against one surviving to the end of a
/// roll. There's still real room for visible "upward movement" well below
/// the ceiling — resting height is ~0.85-1.1, so 2.5 leaves roughly 1.5
/// units of clear bounce above that.
enum PlayfieldVerticalBounds {
    /// Camera height above the floor.
    static let cameraHeight: Float = 15

    /// Height of the invisible ceiling collider above the floor.
    static let ceilingHeight: Float = 2.5
}


// MARK: - The three bands a game screen is split into

/// Header, square scene, button band — the split every game makes.
///
/// It was made eight times, separately, with three different header
/// fractions and a `minButtonHeight` of 100 typed into each one. Three
/// more screens — Boneheads, Royal UR, Baseball Dice — fix their button
/// band outright at 100, 104 and 96.
///
/// Nothing checked any of them at any size. That matters because the band
/// has to hold a known stack of things, and the number guarding it was a
/// round figure that happened to be big enough: the content comes to 95
/// points, Baseball's band is 96, and the margin went from 7 points to 1
/// when the stack spacing in `TurnActionBar` moved from 2 to 8 to keep the
/// button's shadow off its caption. Nothing noticed, because there was
/// nothing to notice with.
///
/// So the arithmetic lives here once, the floor is summed from its own
/// parts rather than typed, and `tools_bandlayout_verify.py` walks it
/// across every size iOS can hand the app.
///
/// `PlayfieldLayout` above is the same idea for the 3D arena — a size in,
/// a measurement out, no view required — which is why this sits beside it
/// rather than in a file of its own.
enum GameBandLayout {

    // MARK: What the button band holds

    /// `.padding(.vertical, 12)`, top and bottom, on the action bar.
    static let bandPadding: CGFloat = 12

    /// The roll button itself.
    static let buttonHeight: CGFloat = 48

    /// Between the button and its caption. The SAME expression the bars
    /// use, so the floor moves when the spacing does instead of being
    /// quietly eaten by it.
    static var captionGap: CGFloat { Elevation.lifted.offset + 2 }

    /// One line of the 12pt caption under the button.
    ///
    /// 15, which is 12 at Poppins' own line height of roughly 1.25. One
    /// line and not two: both bars cap the caption at a single line — see
    /// the note on Rolls' subtitle, which did not and could wrap on a
    /// narrow screen.
    static let captionLine: CGFloat = 15

    /// Everything above, summed. The band may not be shorter than this.
    static var buttonBandFloor: CGFloat {
        bandPadding * 2 + buttonHeight + captionGap + captionLine
    }

    // MARK: The split

    /// The header's share, per game. Boneheads wants a shorter one than
    /// Jackpot, so the fraction stays the caller's business — only the
    /// arithmetic is shared.
    static func header(in size: CGSize, fraction: CGFloat) -> CGFloat {
        size.height * fraction
    }

    /// The square playfield: as wide as the screen, or as tall as what is
    /// left once the header and the button band have theirs.
    ///
    /// Square because the arena and its orthographic camera are built
    /// square — which is also why a wider screen buys the scene nothing,
    /// and why landscape costs these games height for width they cannot
    /// spend.
    static func scene(in size: CGSize, fraction: CGFloat) -> CGFloat {
        let spare = size.height - header(in: size, fraction: fraction)
            - buttonBandFloor
        return min(size.width, max(spare, 0))
    }

    /// Whatever the scene did not take. Never below `buttonBandFloor`,
    /// because the scene gives way first.
    static func buttonBand(in size: CGSize, fraction: CGFloat) -> CGFloat {
        size.height - header(in: size, fraction: fraction)
            - scene(in: size, fraction: fraction)
    }

    /// The header fraction the alternating games share.
    ///
    /// Five screens had the literal `0.17` written three times each — the
    /// same number in fifteen places, and no way to change it without
    /// finding all of them. Free Roll is the exception and still passes its
    /// own, because its header genuinely moves when the totals panel opens.
    static let scoreboardFraction: CGFloat = 0.17

    /// All three band heights at once.
    ///
    /// The five scoreboard games computed the same three values from the
    /// same fraction in the same order, four lines apiece. They each ask one
    /// question — how do I divide this screen — so there is one call that
    /// answers it.
    struct Bands {
        let header: CGFloat
        let scene: CGFloat
        let buttonBand: CGFloat
    }

    static func bands(in size: CGSize,
                      fraction: CGFloat = scoreboardFraction) -> Bands {
        Bands(header: header(in: size, fraction: fraction),
              scene: scene(in: size, fraction: fraction),
              buttonBand: buttonBand(in: size, fraction: fraction))
    }

    /// Whether a fixed band height still holds its content.
    ///
    /// For the three screens that set their own rather than taking the
    /// remainder. Following `GeneralsCardLayout.fits(in:)`, which is the
    /// one place in the app that already asked this question.
    static func fits(band: CGFloat) -> Bool {
        band >= buttonBandFloor
    }
}
