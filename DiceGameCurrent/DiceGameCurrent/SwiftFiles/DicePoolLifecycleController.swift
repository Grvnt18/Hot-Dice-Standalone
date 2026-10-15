import SceneKit
import simd

/// One die that currently exists as a live node in the 3D scene.
struct LiveDie {
    let id: UUID
    let sides: Int
    let node: SCNNode
}

/// Owns the "which dice currently exist in the scene" source of truth.
/// The pool only ever shrinks over a turn (dice get banked, never added
/// back), so this controller's job is: create the initial 15 nodes once,
/// then cleanly remove nodes as their dice get banked — animating them out
/// first rather than just yanking them, and keeping whatever's left in
/// sync with what DiceRollController should roll next.
final class DicePoolLifecycleController {

    private(set) var liveDice: [LiveDie] = []
    private weak var containerNode: SCNNode?

    /// Called just before a new pool replaces the old one, so collaborators
    /// holding per-die state can drop it.
    var onPoolReset: (() -> Void)?

    init(containerNode: SCNNode) {
        self.containerNode = containerNode
    }

    /// Call once, at the start of a turn, to populate the scene with the
    /// full starting pool (all 15 dice). Uses DiceSpawnPattern's fixed,
    /// deterministic slot layout — the slot coordinates never change, so
    /// spacing (and therefore zero spawn overlap) is guaranteed by
    /// construction. What IS randomized here is which physical die lands
    /// in which slot: the dice array is shuffled before being zipped with
    /// the fixed positions, so color placement varies turn to turn while
    /// the underlying pattern stays identical.
    ///
    /// playAreaBounds should come from PlayfieldLayout.compute(...) — no
    /// default here on purpose, since a stale placeholder range silently
    /// accepted would be worse than a compile error reminding the caller
    /// to supply the real, device-derived bounds.
    /// `styleAsRolls` carries Rolls' two cosmetic flourishes — one d6
    /// branded "ROLLS" and one die at 1.5x size. Defaulted to true so Rolls
    /// is unchanged; Free Roll passes false, since in a sandbox where the
    /// player picked each die those would look like defects.
    func setupPool(
        _ dice: [Die],
        playAreaBounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        restHeight: Float = 1.0,
        styleAsRolls: Bool = true,
        alwaysLargest: Bool = false,
        d4Style: DieFaceLabels.D4LabelStyle = .topRead
    ) {
        // Contact-audio cooldown state is keyed on node identity, so it
        // must be cleared alongside the nodes themselves — otherwise it
        // accumulates 15 dead entries per game played.
        onPoolReset?()

        // Tear down any previous pool before building a new one. Starting
        // a second game calls straight through to here, and without this
        // the old dice nodes stay parented to the container — the scene
        // would accumulate 15 more nodes (each with physics bodies and
        // face labels) per game played. In practice a completed game has
        // already removed its dice via bank(), but that relies on every
        // fade-out completion having fired; this makes correctness on
        // repeat not depend on that timing.
        for live in liveDice {
            live.node.removeAllActions()
            live.node.removeFromParentNode()
        }
        liveDice.removeAll()

        let nodesByID = DicePoolSceneBuilder.buildNodes(
            for: dice,
            includeRollsFace: styleAsRolls,
            includeOversizedDie: styleAsRolls,
            alwaysLargest: alwaysLargest,
            d4Style: d4Style
        )
        // The POSITIONS are shuffled, not the dice.
        //
        // This was `dice.shuffled()`, which gave the same spawn variety and
        // cost the pool's ORDER — and `DiceTraySession.finishRoll` reports
        // results "in the pool's own order", a contract a game that reads a
        // die by position depends on. Baseball Dice puts the pitcher's die
        // last and takes `results.last`; against a shuffled pool that was a
        // batter's die two thirds of the time on a favoured at-bat, so the
        // batter was measured against himself.
        //
        // Shuffling which slot each die spawns in achieves what the shuffle
        // was for — a die type does not always start from the same place —
        // without touching the order anything downstream reads.
        let positions = DiceSpawnPattern.positions(
            count: dice.count,
            bounds: playAreaBounds,
            baseHeight: restHeight
        ).shuffled()

        liveDice = dice.enumerated().compactMap { index, die in
            guard let node = nodesByID[die.id] else { return nil }
            node.position = positions[index]
            // Every die used to spawn in the exact same default
            // orientation. If physics then imparts a similar, modest
            // perturbation to each one (plausible given they all get
            // similar impulse magnitudes), they're all starting from —
            // and can end up settling back toward — a shared baseline,
            // which could itself contribute to a bias toward the same
            // face landing up repeatedly. A random starting rotation
            // breaks that shared starting condition, independent of
            // whatever else affects the eventual landed face.
            node.simdOrientation = simd_quatf(
                angle: Float.random(in: 0..<(2 * .pi)),
                axis: simd_normalize(simd_float3(
                    Float.random(in: -1...1),
                    Float.random(in: -1...1),
                    Float.random(in: -1...1)
                ))
            )
            containerNode?.addChildNode(node)
            return LiveDie(id: die.id, sides: die.sides, node: node)
        }
    }

    /// Removes the given dice from the live scene once they've been banked
    /// for score. Fades each one out before detaching it from the scene
    /// graph. Calls completion once every fade has finished.
    func bank(dieIDs: Set<UUID>, completion: (() -> Void)? = nil) {
        let toRemove = liveDice.filter { dieIDs.contains($0.id) }
        liveDice.removeAll { dieIDs.contains($0.id) }

        guard !toRemove.isEmpty else {
            completion?()
            return
        }

        let group = DispatchGroup()
        for live in toRemove {
            group.enter()
            // Cancel the selection pulse first. Banking only ever happens
            // to SELECTED dice, and a selected die is running an infinite
            // repeating opacity animation (DieSelectionHighlight). Left
            // running, that repeating action fights this fade-out on the
            // same property — the die can flicker back to full opacity
            // mid-fade instead of disappearing cleanly. Because every
            // banked die is by definition selected, this conflict fired on
            // every single bank.
            DieSelectionHighlight.setSelected(false, on: live.node)

            let fade = SCNAction.fadeOut(duration: 0.25)

            live.node.runAction(fade) {
                // SCNAction completion handlers can fire off the main
                // thread — hop back before touching the scene graph.
                DispatchQueue.main.async {
                    live.node.removeFromParentNode()
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion?()
        }
    }

    /// Dice still live in the scene, in the shape DiceRollController's
    /// startRoll(dice:currentTime:) expects — hand this straight through
    /// each time a new roll begins.
    var rollableDice: [(id: UUID, node: SCNNode, sides: Int)] {
        liveDice.map { ($0.id, $0.node, $0.sides) }
    }
}
