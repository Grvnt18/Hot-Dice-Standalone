import SceneKit
import UIKit
import simd

// MARK: - Tuning constants

private enum SettleTuning {
    /// Below this linear speed (units/sec), a die counts as "not moving" on a given frame.
    static let linearVelocityThreshold: Float = 0.05
    /// Below this angular speed (rad/sec), a die counts as "not spinning" on a given frame.
    static let angularVelocityThreshold: Float = 0.15
    /// Consecutive still frames required before a die is declared settled.
    /// Prevents a die mid-bounce (briefly slow at the top of an arc) from
    /// being mistaken for settled.
    static let requiredStillFrames = 6

    /// Every roll takes at least this long, regardless of dice count,
    /// so a 1-die roll doesn't feel like an instant, cheap snap.
    static let minRollDuration: TimeInterval = 1.0
    /// Hard ceiling — no roll is allowed to run longer than this, no matter
    /// how many dice or how physics behaves. Raised from 3.5 to 5.0
    /// alongside this round's 2.5-3.5x motion increase: with real
    /// restitution-driven bouncing now happening (vs. the previous
    /// barely-moving physics), 15 dice genuinely need more real time to
    /// finish bouncing, colliding, and separating naturally. At the old
    /// 3.5s cap, more dice were likely hitting the force-settle path
    /// while still overlapping mid-collision — freezing them there
    /// permanently, since a forced settle doesn't wait for clean
    /// separation. This is a likely real contributor to "dice settling on
    /// top of one another."
    static let maxRollDuration: TimeInterval = 5.0
    /// Dice count at which we hit the max duration ceiling.
    static let maxDiceInPool = 15

    /// Duration of the corrective snap that rotates a settled die onto its
    /// nearest valid resting face, ironing out any odd angle left over from
    /// physics jitter or a forced (time-cap) settle.
    static let faceSnapDuration: TimeInterval = 0.16
}

// MARK: - Face normals

/// Local-space face normals for each die shape, used to figure out which
/// face is closest to "resting flat" and snap to it cleanly.
///
/// d6/d8/d10/d12 are extracted directly from the sourced .dae meshes
/// (dice.zip), not estimated. IMPORTANT: the .dae files are authored Z-up
/// (Blender's default) but SceneKit expects Y-up. VERIFIED: every normal
/// below has been checked against the real face normals extracted from
/// the .dae meshes themselves, so this no longer relies on a hand-applied
/// axis conversion being correct. d6/d8 were already right; d10/d12 were
/// not (see the note on those two below) and have been corrected.
///
/// d4/d20 have no sourced .dae to extract from — those meshes are
/// generated in-code (see d4.obj/d20.obj) — so their normals are computed
/// directly from that same generator's vertex/face data instead, which
/// sidesteps the Z-up/Y-up conversion risk entirely (see each one's own
/// comment below).
enum DieFaceNormals {
    /// Computed directly from d4.obj's own generator (a regular tetrahedron
    /// at vertices (1,1,1), (1,-1,-1), (-1,1,-1), (-1,-1,1)) — not measured
    /// from an authored .dae, since these meshes were generated in-code
    /// rather than sourced from Blender. That sidesteps the Z-up/Y-up
    /// conversion risk that caused the d10/d12 bug entirely: whatever axes
    /// the generator used ARE the mesh's local axes, with no separate
    /// export/import convention in between to get wrong. Order matches the
    /// face order used when building d4.obj/d4.dae, which is also the
    /// order DieFaceLabels numbers 1-4 in.
    private static let d4: [SCNVector3] = [
        SCNVector3(0.57735, 0.57735, -0.57735),
        SCNVector3(0.57735, -0.57735, 0.57735),
        SCNVector3(-0.57735, 0.57735, 0.57735),
        SCNVector3(-0.57735, -0.57735, -0.57735)
    ]

    private static let d6: [SCNVector3] = [
        SCNVector3(0.00000, -1.00000, 0.00000),
        SCNVector3(0.00000, 0.00000, 1.00000),
        SCNVector3(-1.00000, 0.00000, 0.00000),
        SCNVector3(1.00000, 0.00000, 0.00000),
        SCNVector3(0.00000, 0.00000, -1.00000),
        SCNVector3(0.00000, 1.00000, 0.00000)
    ]

    private static let d8: [SCNVector3] = [
        SCNVector3(0.57735, 0.57735, -0.57735),
        SCNVector3(-0.57735, 0.57735, -0.57735),
        SCNVector3(-0.57735, 0.57735, 0.57735),
        SCNVector3(0.57735, 0.57735, 0.57735),
        SCNVector3(0.57735, -0.57735, -0.57735),
        SCNVector3(-0.57735, -0.57735, -0.57735),
        SCNVector3(-0.57735, -0.57735, 0.57735),
        SCNVector3(0.57735, -0.57735, 0.57735)
    ]

    // d10/d12 CORRECTED — these were the actual cause of "no numbers
    // visible on d10/d12." The old values had their Y and Z components
    // swapped: the Z-up -> Y-up conversion flagged as "verify this" above
    // was applied incorrectly and never checked. Every single one of the
    // 22 old d10/d12 normals was verified (by extracting real face
    // normals from the .dae meshes) to match NO actual face on the model,
    // so labels were being positioned at coordinates floating off the die
    // or buried inside it, rather than on any face.
    //
    // Why only these two shapes broke: d6's normals are +/-X, +/-Y, +/-Z
    // and d8's are (+/-0.577, +/-0.577, +/-0.577). Both of those sets are
    // CLOSED under a Y/Z swap — a wrongly-converted normal still lands on
    // a real face of the same die, just a different one, which is
    // invisible in practice since face numbering here is arbitrary. d10
    // and d12 have no such symmetry, so the same bug put their labels
    // nowhere at all.
    //
    // Values below are averaged per logical face directly from the mesh
    // (d10's kite faces are each split into 2 triangles that aren't
    // exactly coplanar, so its 20 triangle normals were clustered into
    // the 10 real face directions).
    private static let d10: [SCNVector3] = [
        SCNVector3(-0.86580, 0.45875, 0.19986),
        SCNVector3(0.86580, 0.45875, -0.19986),
        SCNVector3(-0.33524, 0.00000, -0.94213),
        SCNVector3(0.33524, 0.00000, 0.94213),
        SCNVector3(-0.12352, 0.74228, 0.65861),
        SCNVector3(-0.86580, -0.45875, 0.19986),
        SCNVector3(0.12352, -0.74228, -0.65861),
        SCNVector3(0.12352, 0.74228, -0.65861),
        SCNVector3(-0.12352, -0.74228, 0.65861),
        SCNVector3(0.86580, -0.45875, -0.19986)
    ]

    private static let d12: [SCNVector3] = [
        SCNVector3(-0.85065, 0.52573, 0.00000),
        SCNVector3(0.52573, 0.00000, -0.85065),
        SCNVector3(0.85065, 0.52573, 0.00000),
        SCNVector3(-0.52573, 0.00000, -0.85065),
        SCNVector3(0.52573, 0.00000, 0.85065),
        SCNVector3(0.00000, 0.85065, 0.52573),
        SCNVector3(-0.85065, -0.52573, 0.00000),
        SCNVector3(0.00000, -0.85065, -0.52573),
        SCNVector3(0.00000, 0.85065, -0.52573),
        SCNVector3(0.00000, -0.85065, 0.52573),
        SCNVector3(0.85065, -0.52573, 0.00000),
        SCNVector3(-0.52573, 0.00000, 0.85065)
    ]

    /// Same sourcing as d4 above — computed directly from d20.obj's own
    /// generator (a regular icosahedron), not measured from an authored
    /// asset. All 20 verified programmatically to be pairwise distinct
    /// (no accidental duplicate/mirrored face, the class of bug that hit
    /// the old hand-derived d10/d12 values) and unit length. Order matches
    /// the face order used when building d20.obj/d20.dae.
    private static let d20: [SCNVector3] = [
        SCNVector3(-0.57735, 0.57735, 0.57735),
        SCNVector3(0.00000, 0.93417, 0.35682),
        SCNVector3(0.00000, 0.93417, -0.35682),
        SCNVector3(-0.57735, 0.57735, -0.57735),
        SCNVector3(-0.93417, 0.35682, 0.00000),
        SCNVector3(0.57735, 0.57735, 0.57735),
        SCNVector3(-0.35682, 0.00000, 0.93417),
        SCNVector3(-0.93417, -0.35682, 0.00000),
        SCNVector3(-0.35682, 0.00000, -0.93417),
        SCNVector3(0.57735, 0.57735, -0.57735),
        SCNVector3(0.57735, -0.57735, 0.57735),
        SCNVector3(0.00000, -0.93417, 0.35682),
        SCNVector3(0.00000, -0.93417, -0.35682),
        SCNVector3(0.57735, -0.57735, -0.57735),
        SCNVector3(0.93417, -0.35682, 0.00000),
        SCNVector3(0.35682, 0.00000, 0.93417),
        SCNVector3(-0.57735, -0.57735, 0.57735),
        SCNVector3(-0.57735, -0.57735, -0.57735),
        SCNVector3(0.35682, 0.00000, -0.93417),
        SCNVector3(0.93417, 0.35682, 0.00000)
    ]

    static func normals(forSides sides: Int) -> [SCNVector3] {
        switch sides {
        case 4: return d4
        case 6: return d6
        case 8: return d8
        case 10: return d10
        case 12: return d12
        case 20: return d20
        default: return d6
        }
    }
}

// MARK: - Per-die tracking state

private final class DieSettleState {
    let node: SCNNode
    let dieID: UUID
    var stillFrameStreak = 0
    /// Flips true the instant settle() starts (physics frozen) — this is
    /// what stops the frame loop from re-entering settle() for the same
    /// die on every subsequent frame, since a frozen kinematic body reports
    /// zero velocity and would otherwise look "still" forever.
    var isSettled = false
    /// Flips true only once the snap animation AND badge reveal have
    /// actually finished — this is what onRollComplete's "has everything
    /// really finished" check should read, kept separate from isSettled
    /// so the two concerns (stop reprocessing vs. roll is visually done)
    /// don't collide.
    var isFullyRevealed = false

    init(node: SCNNode, dieID: UUID) {
        self.node = node
        self.dieID = dieID
    }
}

// MARK: - Roll controller

/// Drives one roll: applies random impulses to the given die nodes, watches
/// each one's physics body every frame, and fires a callback the instant a
/// die settles (or is force-settled once the roll's time budget expires).
final class DiceRollController: NSObject, SCNSceneRendererDelegate {

    /// Called once per die, the moment it settles (naturally or forced),
    /// with the value read from whichever face actually landed up — this
    /// is now the true scored result (see FaceSnapping's returned face
    /// index), not just a cosmetic rotation.
    var onDieSettled: ((UUID, SCNNode, Int) -> Void)?

    /// Called once, after every die in the roll has settled.
    var onRollComplete: (() -> Void)?

    /// Dice from the current roll that have finished settling (including
    /// their face-snap animation) and are legal to tap-select. Cleared at
    /// the start of each new roll.
    private(set) var settledDieIDs: Set<UUID> = []

    /// True from the moment a roll starts until every die in it has fully
    /// settled. Exposed so the turn/UI layer can block starting another
    /// roll while one is still in progress — without this, a die that
    /// settles fast (while others from the same roll are still tumbling)
    /// becomes individually tap-selectable, and pressing Roll/Finish at
    /// that point would call startRoll(...) again, which unconditionally
    /// resets trackedDice — silently abandoning whichever dice were still
    /// mid-flight from the roll that was still in progress.
    private(set) var isRolling = false

    /// Playfield extent and floor height, used by the containment safety
    /// net below. Set by DiceSceneAssembler so they agree with the
    /// physics colliders and camera framing.
    var playAreaBounds: (x: ClosedRange<Float>, z: ClosedRange<Float>)?
    var floorY: Float = 0
    /// Height of the invisible ceiling collider above floorY — see
    /// PlayfieldVerticalBounds for why the camera, the ceiling collider,
    /// and this all read from the same number.
    var ceilingY: Float = PlayfieldVerticalBounds.ceilingHeight

    /// How many times each die has been nudged off a stack this roll.
    /// Capped so a pathological arrangement can't nudge forever and stop
    /// the turn from ever completing.
    private var rollOffAttempts: [UUID: Int] = [:]
    private let maxRollOffAttempts = 3

    /// World-space half-extents of a die, accounting for its randomized
    /// scale. Used by both stack detection and the final separation pass.
    private func halfExtents(_ node: SCNNode) -> (radius: Float, height: Float) {
        let bb = node.boundingBox
        let hx = (bb.max.x - bb.min.x) / 2 * node.scale.x
        let hy = (bb.max.y - bb.min.y) / 2 * node.scale.y
        let hz = (bb.max.z - bb.min.z) / 2 * node.scale.z
        return (max(hx, hz), hy)
    }

    /// If `state` is about to come to rest ON TOP of another die, shove it
    /// off instead of letting it settle there.
    ///
    /// This is the physical counterpart to the geometric separation pass
    /// that runs at the end of a roll. Rather than teleporting a stacked
    /// die sideways after the fact, this catches it at the moment it would
    /// settle and gives it a real impulse plus tumbling torque, so it rolls
    /// off the die beneath under normal physics and settles naturally
    /// wherever it lands. The result looks like a die that never balanced
    /// in the first place, which is the point.
    ///
    /// Returns true if the die was nudged and should NOT settle yet.
    private func attemptRollOff(_ state: DieSettleState) -> Bool {
        guard let body = state.node.physicsBody else { return false }
        let attempts = rollOffAttempts[state.dieID] ?? 0
        guard attempts < maxRollOffAttempts else { return false }

        let me = halfExtents(state.node)
        let myPos = state.node.presentation.position

        for other in trackedDice where other.dieID != state.dieID {
            let theirs = halfExtents(other.node)
            let theirPos = other.node.presentation.position

            let dx = myPos.x - theirPos.x
            let dz = myPos.z - theirPos.z
            let horizontal = sqrt(dx * dx + dz * dz)
            // Overlapping in plan view...
            guard horizontal < (me.radius + theirs.radius) * 0.85 else { continue }
            // ...and genuinely sitting above, not merely beside. Requiring
            // most of the lower die's height avoids firing on two dice
            // resting side by side on the floor with slightly different
            // centres.
            guard myPos.y - theirPos.y > theirs.height * 0.6 else { continue }

            rollOffAttempts[state.dieID] = attempts + 1

            // Push away from the die underneath. Degenerate case (perfectly
            // concentric) gets a fixed direction rather than NaN.
            var nx = dx, nz = dz
            if horizontal < 0.0001 { nx = 1; nz = 0 } else { nx /= horizontal; nz /= horizontal }

            body.type = .dynamic
            body.velocity = SCNVector3Zero
            body.angularVelocity = SCNVector4(0, 1, 0, 0)

            // Sideways and slightly up: enough to clear the edge it's
            // perched on, not enough to launch it across the table.
            let push: Float = 2.6
            body.applyForce(SCNVector3(nx * push, 1.1, nz * push), asImpulse: true)
            // Torque about the axis perpendicular to the push makes it
            // topple in the direction it's travelling.
            body.applyTorque(SCNVector4(-nz, 0, nx, 1.4), asImpulse: true)

            state.stillFrameStreak = 0
            return true
        }
        return false
    }

    private var trackedDice: [DieSettleState] = []
    private var rollStartTime: TimeInterval = 0
    private var maxDurationForThisRoll: TimeInterval = SettleTuning.minRollDuration

    /// Time budget scales linearly from minRollDuration (1 die) up to
    /// maxRollDuration (15 dice, or however many are in the pool at once).
    private func timeBudget(forDiceCount count: Int) -> TimeInterval {
        let clampedCount = max(1, min(count, SettleTuning.maxDiceInPool))
        let progress = Double(clampedCount - 1) / Double(SettleTuning.maxDiceInPool - 1)
        return SettleTuning.minRollDuration
            + progress * (SettleTuning.maxRollDuration - SettleTuning.minRollDuration)
    }

    /// Start a roll for the given (dieID, physicsNode) pairs. Each node must
    /// already have an SCNPhysicsBody attached and an impulse/torque applied
    /// by whatever kicks off the visual tumble.
    func startRoll(dice: [(id: UUID, node: SCNNode, sides: Int)], currentTime: TimeInterval) {
        trackedDice = dice.map { DieSettleState(node: $0.node, dieID: $0.id) }
        dieSidesByID = Dictionary(uniqueKeysWithValues: dice.map { ($0.id, $0.sides) })
        settledDieIDs.removeAll()
        rollOffAttempts.removeAll()
        rollStartTime = currentTime
        maxDurationForThisRoll = timeBudget(forDiceCount: dice.count)
        isRolling = true
    }

    // Called every frame by SceneKit while this object is the scene's delegate.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard isRolling else { return }

        let elapsed = time - rollStartTime
        let timeIsUp = elapsed >= maxDurationForThisRoll

        applyRepulsion(elapsed: elapsed)
        enforceContainment()

        for state in trackedDice where !state.isSettled {
            guard let body = state.node.physicsBody else { continue }

            if timeIsUp {
                forceSettle(state)
                continue
            }

            if isEffectivelyStill(body) {
                state.stillFrameStreak += 1
                if state.stillFrameStreak >= SettleTuning.requiredStillFrames {
                    settle(state)
                }
            } else {
                state.stillFrameStreak = 0
            }
        }

        if trackedDice.allSatisfy({ $0.isFullyRevealed }) {
            resolveStacking()
            isRolling = false
            DispatchQueue.main.async { [weak self] in
                self?.onRollComplete?()
            }
        }
    }

    /// Guarantees no die ends a roll resting on top of another.
    ///
    /// Repulsion-during-flight reduces stacking but cannot rule it out —
    /// it's a force nudging a simulation, and the simulation gets the
    /// final say. This runs once, after every die has settled and gone
    /// kinematic, when positions are fixed and nothing can push back. It
    /// treats each die as a circle in the XZ plane and relaxes overlaps
    /// apart, then puts every die down at floor level. Because the dice
    /// are kinematic by this point, the result is final: a die physically
    /// cannot be above another one afterwards.
    ///
    /// The relaxation is the standard iterative pairwise separation used
    /// for circle packing — each pass pushes overlapping pairs apart by
    /// half their overlap each, converging in a handful of passes at this
    /// scale (at most 15 circles).
    private func resolveStacking() {
        guard let bounds = playAreaBounds, trackedDice.count > 1 else { return }

        struct Placed {
            let node: SCNNode
            var x: Float
            var z: Float
            let radius: Float
            let restY: Float
        }

        var placed: [Placed] = trackedDice.compactMap { state in
            let node = state.node
            // Same extents helper the roll-off detection uses, so the two
            // systems agree on how big each die is.
            let e = halfExtents(node)
            let p = node.presentation.position
            return Placed(node: node, x: p.x, z: p.z,
                          radius: e.radius, restY: floorY + e.height)
        }

        for _ in 0..<24 {
            var moved = false
            for i in 0..<placed.count {
                for j in (i + 1)..<placed.count {
                    let dx = placed[j].x - placed[i].x
                    let dz = placed[j].z - placed[i].z
                    let minDist = placed[i].radius + placed[j].radius
                    var dist = sqrt(dx * dx + dz * dz)
                    guard dist < minDist else { continue }

                    // Exactly coincident centres have no separation
                    // direction; nudge along a fixed axis to break the tie
                    // rather than dividing by zero.
                    var nx: Float = 1, nz: Float = 0
                    if dist > 0.0001 {
                        nx = dx / dist; nz = dz / dist
                    } else {
                        dist = 0.0001
                    }

                    let push = (minDist - dist) / 2
                    placed[i].x -= nx * push; placed[i].z -= nz * push
                    placed[j].x += nx * push; placed[j].z += nz * push
                    moved = true
                }
            }
            // Keep everything inside the playfield after each pass, so
            // separation can't walk a die through a wall.
            for k in 0..<placed.count {
                let r = placed[k].radius
                placed[k].x = min(max(placed[k].x, bounds.x.lowerBound + r), bounds.x.upperBound - r)
                placed[k].z = min(max(placed[k].z, bounds.z.lowerBound + r), bounds.z.upperBound - r)
            }
            if !moved { break }
        }

        for p in placed {
            let target = SCNVector3(p.x, p.restY, p.z)
            let current = p.node.presentation.position
            let delta = SCNVector3(target.x - current.x, target.y - current.y, target.z - current.z)
            let distance = sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
            // Leave untouched anything already effectively in place, so a
            // clean roll isn't given a pointless settling twitch.
            guard distance > 0.01 else { continue }
            // Sync node.position to the simulated position before
            // animating. Everything above is computed from
            // presentation.position (where physics actually left the die),
            // but SCNAction.move interpolates from node.position — if the
            // two have diverged, the die visibly jumps to the stale
            // position before sliding to its target.
            p.node.position = current
            let move = SCNAction.move(to: target, duration: 0.18)
            move.timingMode = .easeOut
            p.node.runAction(move)
        }
    }

    /// Last-resort containment. Everything upstream is meant to prevent
    /// a die leaving the play area — thicker wall colliders, a clamped
    /// repulsion force, an actual floor and ceiling collider (see
    /// DicePlayfieldPhysics.makeContainer / PlayfieldVerticalBounds). This
    /// exists because none of that is a guarantee: physics engines can
    /// tunnel under enough velocity, a solver can push overlapping bodies
    /// apart violently, and a die that escapes is unrecoverable (it falls
    /// or climbs forever, the roll never settles, and the turn can never
    /// complete).
    ///
    /// Cheap to run and impossible to notice when it does nothing, which
    /// is the right trade for a failure this severe.
    private func enforceContainment() {
        guard let bounds = playAreaBounds else { return }

        for state in trackedDice where !state.isSettled {
            guard let body = state.node.physicsBody else { continue }
            let p = state.node.presentation.position

            // Margin lets a die legitimately touch the wall without being
            // yanked; only a genuine escape trips this.
            let margin: Float = 0.5
            let outOfX = p.x < bounds.x.lowerBound - margin || p.x > bounds.x.upperBound + margin
            let outOfZ = p.z < bounds.z.lowerBound - margin || p.z > bounds.z.upperBound + margin
            let belowFloor = p.y < floorY - 1.0
            // Symmetric to belowFloor: a die that somehow tunnels through
            // the ceiling collider (or gets there before it, on the very
            // first frame after an escalated-repulsion collision) is just
            // as unrecoverable as one that falls through the floor — it
            // closes on the camera's near plane and vanishes rather than
            // falling forever, but the failure (falls never settles, turn
            // never completes) is identical.
            let aboveCeiling = p.y > ceilingY + 1.0
            guard outOfX || outOfZ || belowFloor || aboveCeiling else { continue }

            // Put it back just inside, drop its velocity, and let physics
            // resume normally from there. Zeroing velocity matters: a die
            // repositioned while still travelling at escape speed would
            // simply tunnel straight back out on the next step.
            let clampedX = min(max(p.x, bounds.x.lowerBound + margin), bounds.x.upperBound - margin)
            let clampedZ = min(max(p.z, bounds.z.lowerBound + margin), bounds.z.upperBound - margin)
            let clampedY = aboveCeiling ? ceilingY - 1.0 : floorY + 1.0
            state.node.position = SCNVector3(clampedX, clampedY, clampedZ)
            body.resetTransform()
            body.velocity = SCNVector3Zero
            body.angularVelocity = SCNVector4(0, 1, 0, 0)
            print("[DiceRollController] contained an escaped die")
        }
    }

    /// Gently pushes nearby, still-active dice apart — specifically aimed
    /// at preventing dice from settling stacked on top of one another,
    /// which becomes more likely once real bouncing/collision physics is
    /// actually working (dice have real momentum to lose, and losing it
    /// near another die can leave them overlapping). Deliberately WEAK
    /// while a die is still moving fast (avoids fighting the lively
    /// mid-roll tumbling/collisions that are the whole point), and
    /// stronger as it slows down — "momentum bleeds out" is exactly the
    /// window this targets. Continuous force (not impulse), so it reads
    /// as a soft, physical-feeling nudge rather than a sudden kick.
    ///
    /// Past 3.5s into the roll, this stops being gentle: the speed-based
    /// gate is bypassed entirely (any overlap gets pushed apart regardless
    /// of how fast either die is moving) and the force magnitude ramps up
    /// aggressively toward the 5.0s hard settle cap — by explicit request,
    /// staying stacked needs to be physically impossible by then, not just
    /// unlikely.
    private func applyRepulsion(elapsed: TimeInterval) {
        // Range widened and force raised substantially. The oversized die
        // (up to 1.5x) has a half-extent near 0.75, so the old 1.1 range
        // could let a big die and a normal one overlap without ever
        // triggering separation.
        let repulsionDistance: Float = 1.6
        let baseForce: Float = 18.0
        let speedCeiling: Float = 3.0 // above this speed, gentle-phase repulsion is fully off

        let escalationStart: TimeInterval = 3.5
        let escalationEnd: TimeInterval = SettleTuning.maxRollDuration // 5.0 — by the hard cap, force is at its strongest
        let isEscalating = elapsed >= escalationStart
        let escalationProgress = isEscalating
            ? min(1.0, (elapsed - escalationStart) / max(escalationEnd - escalationStart, 0.001))
            : 0
        // Ramps from 1x up to 40x. Combined with the higher base force,
        // a stacked pair in the final stretch gets pushed apart hard
        // enough that resting on top of another die isn't survivable.
        let escalationMultiplier: Float = 1.0 + Float(escalationProgress) * 39.0

        let active = trackedDice.filter { !$0.isSettled }
        guard active.count > 1 else { return }

        for i in 0..<active.count {
            guard let bodyA = active[i].node.physicsBody else { continue }
            let posA = active[i].node.presentation.position
            let speedA = length(bodyA.velocity)

            for j in (i + 1)..<active.count {
                guard let bodyB = active[j].node.physicsBody else { continue }
                let posB = active[j].node.presentation.position

                let delta = SCNVector3(posA.x - posB.x, posA.y - posB.y, posA.z - posB.z)
                let distance = length(delta)
                guard distance < repulsionDistance, distance > 0.001 else { continue }

                // Before 3.5s: gated by speed, so this doesn't fight
                // genuine mid-roll tumbling. After 3.5s: the gate is
                // bypassed entirely — at this point in the roll, any
                // remaining overlap needs to be resolved regardless of
                // how slow (or momentarily fast, e.g. from a late
                // collision) the dice involved are moving.
                let slownessFactor: Float
                if isEscalating {
                    slownessFactor = 1.0
                } else {
                    let speedB = length(bodyB.velocity)
                    let averageSpeed = (speedA + speedB) / 2
                    slownessFactor = 1.0 - min(averageSpeed / speedCeiling, 1.0)
                }

                let overlap = (repulsionDistance - distance) / repulsionDistance
                var magnitude = baseForce * overlap * slownessFactor * escalationMultiplier
                guard magnitude > 0.001 else { continue }

                // Clamp. This is a CONTINUOUS force re-applied every
                // frame, so it compounds: at the escalated ceiling it was
                // adding ~6 units/s of velocity per frame, reaching ~60
                // units/s after 10 frames of sustained overlap — past the
                // tunneling threshold for both the walls and the floor.
                // A separation nudge doesn't need to be able to launch a
                // die out of the world; 60 caps the per-frame velocity
                // gain at 0.5 units/s, which still separates a stack
                // quickly but can never reach escape speed.
                magnitude = min(magnitude, 60)

                // Separate HORIZONTALLY only. The previous version added an
                // upward component to both bodies, which was actively
                // counterproductive for the case it was meant to fix:
                // lifting the LOWER die drives it into the one resting on
                // top, helping the stack persist instead of breaking it.
                // Horizontal-only separation slides the pair apart and lets
                // gravity do the rest.
                var hx = delta.x, hz = delta.z
                var hLen = sqrt(hx * hx + hz * hz)
                if hLen < 0.0001 {
                    // Exactly stacked: no horizontal direction exists, so
                    // pick one deterministically rather than dividing by
                    // zero and leaving the pair welded together.
                    hx = 1; hz = 0; hLen = 1
                }
                hx /= hLen; hz /= hLen

                let forceOnA = SCNVector3(hx * magnitude, 0, hz * magnitude)
                let forceOnB = SCNVector3(-forceOnA.x, 0, -forceOnA.z)

                // Whichever die is higher also gets a spin about the
                // horizontal axis perpendicular to the push, so it tumbles
                // off rather than sliding off flat — that's what makes the
                // separation read as a die rolling off another instead of
                // being shoved sideways.
                let upper = posA.y > posB.y ? bodyA : bodyB
                let spinSign: Float = posA.y > posB.y ? 1 : -1
                upper.applyTorque(
                    SCNVector4(-hz * spinSign, 0, hx * spinSign, magnitude * 0.25),
                    asImpulse: false
                )

                bodyA.applyForce(forceOnA, asImpulse: false)
                bodyB.applyForce(forceOnB, asImpulse: false)
            }
        }
    }

    private func isEffectivelyStill(_ body: SCNPhysicsBody) -> Bool {
        let linearSpeed = length(body.velocity)
        let angularSpeed = abs(body.angularVelocity.w) // rotation speed around the axis
        return linearSpeed < SettleTuning.linearVelocityThreshold
            && angularSpeed < SettleTuning.angularVelocityThreshold
    }

    /// dieSides lets settle() look up the right face-normal set for the snap.
    /// Populate this when starting a roll (see startRoll).
    private var dieSidesByID: [UUID: Int] = [:]

    private func settle(_ state: DieSettleState, allowRollOff: Bool = true) {
        // Set immediately (synchronously), not deferred to the animation
        // completion below — this is what stops the frame loop from
        // re-entering settle() for this same die on every subsequent
        // frame. A frozen kinematic body reports zero velocity, so
        // isEffectivelyStill would otherwise keep returning true
        // indefinitely, re-triggering settle() (and stacking multiple
        // badge reveals) every frame until the snap animation finishes.
        state.isSettled = true

        guard let body = state.node.physicsBody else { return }

        // Before freezing: if this die is coming to rest on top of another,
        // knock it off and let it settle somewhere legitimate instead.
        //
        // Skipped on a forced settle. forceSettle runs at the hard time
        // cap, and its whole job is to guarantee the roll ends — allowing
        // a nudge there would leave the die unsettled with no time left to
        // re-settle, so isRolling would never clear and the turn would
        // hang. The geometric separation pass still cleans up afterwards.
        if allowRollOff, attemptRollOff(state) { return }

        // Freeze physics control of this die so our snap animation isn't
        // fought by the physics engine, then rotate onto the nearest valid
        // resting face before revealing anything — covers both a naturally
        // settled die with slight jitter and a force-settled one that may
        // have been frozen mid-tumble.
        //
        // Captured BEFORE switching to kinematic, not after — this is the
        // actual fix for the "every die shows its own maximum face" bug.
        // See FaceSnapping.snap's doc comment for the full explanation.
        let trueOrientation = state.node.presentation.orientation

        body.velocity = SCNVector3Zero
        body.angularVelocity = SCNVector4(0, 1, 0, 0)
        body.type = .kinematic

        let sides = dieSidesByID[state.dieID] ?? 6
        let normals = DieFaceNormals.normals(forSides: sides)

        FaceSnapping.snap(
            node: state.node,
            fromOrientation: trueOrientation,
            faceNormals: normals,
            // A d4 is read at its apex, so what matters is which face it
            // came to rest ON — see FaceSnapping.snap's doc comment.
            alignFace: sides == 4 ? .down : .up
        ) { [weak self] landedFaceIndex in
            // Only now, once the snap animation has actually finished, is
            // this die's reveal considered fully complete — see
            // isFullyRevealed's doc comment for why this is tracked
            // separately from isSettled above.
            state.isFullyRevealed = true
            self?.settledDieIDs.insert(state.dieID)
            // Face index -> value uses the same 1-through-sides,
            // index-order convention as DieFaceLabels — the permanent
            // label physically showing on the landed face and the value
            // recorded here for scoring are now guaranteed to match,
            // since they both come from the same face-index numbering.
            //
            // The d4 is the exception, and what it reports is deliberately
            // the RESTING face rather than a reading. A tetrahedron has no
            // up face, and there are now two ways to label one — top-read
            // (one value at the apex) and face-numbers (three values, one
            // per visible face) — so any single "value" here would bake
            // one game's interpretation into the physics layer. The
            // resting face is the raw physical fact, unambiguous because
            // it is the face snapped downward. Callers interpret it with
            // DieFaceLabels.d4ApexValue(restingFace:) or
            // .d4ExposedFaceNumbers(restingFace:).
            let value = landedFaceIndex + 1
            // No settle sound here: DiceContactAudio now plays a real
            // impact for the final contact that brought this die to rest.
            // Firing another sound at the same moment would double it.
            self?.onDieSettled?(state.dieID, state.node, value)
        }
    }

    /// Time budget ran out with this die still moving — stop it dead and
    /// settle it anyway. Physics is inherently unpredictable with lots of
    /// dice colliding, so this guarantees the roll never overruns the cap.
    private func forceSettle(_ state: DieSettleState) {
        settle(state, allowRollOff: false)
    }

    private func length(_ v: SCNVector3) -> Float {
        sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    }
}

// MARK: - Face snapping

enum FaceSnapping {

    /// Rotates `node` from its current orientation to whichever valid
    /// resting orientation is closest, so it ends up lying flat on a real
    /// face rather than at a jittery or forced-freeze angle.
    ///
    /// `fromOrientation` must be captured by the CALLER before switching
    /// the body to kinematic — reading node.presentation.orientation
    /// internally, after that switch, was the actual bug behind "every die
    /// shows its own maximum face": a dynamic physics body's true tumbled
    /// rotation only ever lives in its simulation-driven presentation
    /// transform, not the node's own regular orientation property. The
    /// instant a body switches to kinematic, presentation resets to that
    /// stale, near-identity orientation, discarding the real rotation —
    /// so every die was being evaluated as if it had never moved at all,
    /// and whichever face's normal happens to point closest to "up" in a
    /// given shape's raw untransformed data won every single time.
    ///
    /// Calls `completion` once the animation finishes, passing the INDEX
    /// (into `faceNormals`) of whichever face ended up aligned with
    /// `alignFace` — the die's actual scored value is derived from it, so
    /// this is meaningful rather than cosmetic.
    ///
    /// `alignFace` is `.up` for every die except the d4. A tetrahedron has
    /// no face pointing up when it rests: the resting face points straight
    /// down and the other three sit at exactly the same angle, all reading
    /// +0.333 against +Y. Picking "closest to up" from those three is a
    /// three-way tie broken only by floating-point noise, and rotating the
    /// winner to point straight up would tip the die ~70 degrees onto an
    /// edge. Aligning the resting face DOWN is unambiguous, and it is the
    /// pose physics already settled into, so the correction stays small.
    enum FaceAlignment {
        case up
        case down

        var worldDirection: simd_float3 {
            switch self {
            case .up:   return simd_float3(0, 1, 0)
            case .down: return simd_float3(0, -1, 0)
            }
        }
    }

    static func snap(
        node: SCNNode,
        fromOrientation: SCNQuaternion,
        faceNormals: [SCNVector3],
        alignFace: FaceAlignment = .up,
        completion: ((Int) -> Void)? = nil
    ) {
        guard !faceNormals.isEmpty else {
            completion?(0)
            return
        }

        let currentQuat = fromOrientation.simd
        let target = alignFace.worldDirection

        // Find which local face normal currently points closest to the
        // target direction (world up for most dice, world down for a d4).
        var bestNormal = faceNormals[0].simd
        var bestDot: Float = -.greatestFiniteMagnitude
        var bestIndex = 0
        for (index, normal) in faceNormals.enumerated() {
            let worldNormal = currentQuat.act(normal.simd)
            let dot = simd_dot(worldNormal, target)
            if dot > bestDot {
                bestDot = dot
                bestNormal = normal.simd
                bestIndex = index
            }
        }

        // Rotation that takes that face normal the rest of the way to
        // pointing exactly along the target direction.
        let currentWorldNormal = currentQuat.act(bestNormal)
        let correction = simd_quatf(from: currentWorldNormal, to: target)
        let targetQuat = simd_normalize(correction * currentQuat)

        let duration = SettleTuning.faceSnapDuration
        let action = SCNAction.customAction(duration: duration) { animatedNode, elapsedTime in
            let t = duration > 0 ? Float(elapsedTime) / Float(duration) : 1
            let interpolated = simd_slerp(currentQuat, targetQuat, min(max(t, 0), 1))
            animatedNode.simdOrientation = interpolated
        }

        node.runAction(action) {
            completion?(bestIndex)
        }
    }
}

private extension SCNQuaternion {
    var simd: simd_quatf {
        simd_quatf(ix: Float(x), iy: Float(y), iz: Float(z), r: Float(w))
    }
}
// SCNVector3.simd used to be duplicated here — consolidated into
// SharedExtensions.swift after a full-codebase review found it
// independently, identically defined in two files.
