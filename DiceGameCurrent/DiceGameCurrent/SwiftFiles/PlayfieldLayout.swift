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

    /// Centre offset for a visible wall panel, measured inward from the
    /// nominal bound.
    static var visualCentreOffset: Float { visualThickness / 2 - outwardOverhang }

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
    /// addOneWall). DiceScoreBar's header background is painted with the
    /// same fraction of its own on-screen width, rather than stretching one
    /// copy across the whole bar — that's what keeps the plank pitch
    /// continuous across the seam between the header and the walls instead
    /// of jumping to a different scale right where they meet.
    static let woodTileFraction: Float = 0.4
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
