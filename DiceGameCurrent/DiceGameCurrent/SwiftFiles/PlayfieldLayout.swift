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
}
