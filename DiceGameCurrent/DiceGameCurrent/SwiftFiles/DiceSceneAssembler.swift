import SceneKit

/// Everything needed to actually run a turn, handed back after assembly so
/// the caller (your SwiftUI view/coordinator) can drive the game without
/// needing to know how any of these pieces were wired together.
struct DiceGameSession {
    let scene: SCNScene
    /// The round present at assembly time. NOTE: once a game finishes and
    /// "Begin" starts a new one, DiceTurnController swaps in a fresh
    /// DiceGameRound internally — this stored reference does NOT follow
    /// that swap and will go stale. Go through turnController
    /// (currentScore, bankedOrder, recordSettledValue(dieID:value:), etc.)
    /// for anything that needs to reflect the currently active round;
    /// don't read this property after a game has restarted.
    let round: DiceGameRound
    let lifecycle: DicePoolLifecycleController
    let rollController: DiceRollController
    let turnController: DiceTurnController
    let tapHandler: DiceTapHandler
    /// Retained here because SCNPhysicsWorld.contactDelegate is a WEAK
    /// reference — without a strong reference living as long as the
    /// session, this would deallocate immediately after assemble()
    /// returns and no contact sounds would ever play.
    let contactAudio: DiceContactAudio
}

/// Assembles one complete dice scene into a given SCNView: computes the
/// device-appropriate playfield layout, builds the camera/lighting/floor/
/// physics container, configures the physics world, and wires the roll
/// controller in as the view's render delegate — all the plumbing steps
/// that have to happen in the right order for anything to actually work,
/// gathered into one place rather than left for the caller to remember.
enum DiceSceneAssembler {

    /// Call once sceneView has a real, non-zero size (e.g. after SwiftUI
    /// layout has run) — the playfield layout is derived from its actual
    /// on-screen aspect ratio.
    static func assemble(
        into sceneView: SCNView
    ) -> DiceGameSession {
        // Called here, as the very first thing — not relied upon via
        // SwiftUI's .onAppear on some outer view. That was the actual bug
        // behind the gameplay area failing to render: .onAppear (where
        // font registration happened) is on the outer view, while THIS
        // function runs inside updateUIView on a nested UIViewRepresentable
        // — nothing guarantees the outer .onAppear fires first. If it
        // didn't, DiceSceneEnvironment.addFloorText's font lookup silently
        // failed, producing a zero-size image, which produced an SCNPlane
        // with height=0 — degenerate geometry created right in the middle
        // of assembly. Calling registration here, as literally the first
        // line of the one function that's guaranteed to run before
        // anything in the scene touches these fonts, removes the race
        // entirely rather than hoping view-lifecycle ordering cooperates.
        AppFonts.registerIfNeeded()

        let scene = SCNScene()
        sceneView.scene = scene

        // We're supplying our own lights explicitly below — leaving this
        // on would add an extra, uncontrolled light fighting the area
        // light and flattening the shading we set up on purpose.
        sceneView.autoenablesDefaultLighting = false

        let floorY: Float = 0
        let aspectRatio = Float(sceneView.bounds.width / max(sceneView.bounds.height, 1))
        let layout = PlayfieldLayout.compute(screenAspectRatio: aspectRatio)

        DicePhysicsWorldConfigurator.configure(scene.physicsWorld)

        let cameraNode = DiceCameraFactory.makeTopDownCamera(
            playfieldBounds: layout.bounds,
            orthographicScale: layout.orthographicScale,
            floorY: floorY
        )
        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode

        DiceSceneEnvironment.addLighting(
            to: scene.rootNode,
            playfieldBounds: layout.bounds,
            floorY: floorY
        )

        DiceSceneEnvironment.addFloorSurface(
            to: scene.rootNode,
            bounds: layout.bounds,
            floorY: floorY
        )

        DiceSceneEnvironment.addFloorText(
            to: scene.rootNode,
            bounds: layout.bounds,
            floorY: floorY
        )

        // Visual height only — the actual containment boundary (in
        // DicePlayfieldPhysics.makeContainer below) is much taller and
        // invisible, guaranteeing dice can never physically escape
        // regardless of roll energy. This is sized to look like a
        // reasonable dice-tray rim relative to the playfield, not to
        // survive any particular bounce height.
        DiceSceneEnvironment.addWalls(
            to: scene.rootNode,
            bounds: layout.bounds,
            floorY: floorY,
            visualHeight: 10.4 // doubled again from 5.2 per request
        )

        let playfieldContainer = DicePlayfieldPhysics.makeContainer(
            bounds: layout.bounds,
            floorY: floorY
        )
        scene.rootNode.addChildNode(playfieldContainer)

        // Dice live under their own container node rather than directly on
        // the scene root — keeps the scene graph organized and gives
        // DicePoolLifecycleController one clear parent to add/remove from.
        let diceContainer = SCNNode()
        diceContainer.name = "diceContainer"
        scene.rootNode.addChildNode(diceContainer)

        let round = DiceGameRound()
        let lifecycle = DicePoolLifecycleController(containerNode: diceContainer)
        lifecycle.setupPool(round.pool, playAreaBounds: layout.bounds)

        let rollController = DiceRollController()
        // Containment safety net needs to agree with the colliders and
        // camera on where the playfield actually is.
        rollController.playAreaBounds = layout.bounds
        rollController.floorY = floorY

        let turnController = DiceTurnController(
            round: round,
            lifecycle: lifecycle,
            rollController: rollController,
            playAreaBounds: layout.bounds
        )

        // The die's true scored value now comes directly from whichever
        // face physically landed up (see FaceSnapping's returned face
        // index in DiceRollController) — no separate badge reveal needed
        // anymore, the permanent face label already visible on that
        // landed face IS the value. This just needs to write it into the
        // game's logic layer for scoring. Goes through
        // turnController.recordSettledValue(...) rather than writing to
        // `round` directly — turnController swaps in a fresh round when a
        // finished game restarts (see DiceTurnController.startNewGameAndRoll),
        // so a closure that captured the original round object would
        // silently keep writing to a stale, abandoned round after the
        // first game ends.
        rollController.onDieSettled = { [weak turnController] dieID, _, value in
            turnController?.recordSettledValue(dieID: dieID, value: value)
        }
        // Found during review: rollController.isRolling now gates the
        // Roll button (see DiceTurnController.canConfirmAndRoll), but
        // isRolling flips false inside the roll controller's own
        // per-frame update — on a DIFFERENT frame than the last die's
        // settle callback fires. Without this, nothing would tell the UI
        // to re-check canConfirmAndRoll at the moment it actually becomes
        // true again, which could leave the Roll button stuck disabled
        // after a roll genuinely finishes. onRollComplete already fires
        // exactly at that transition — it was defined but never actually
        // wired to anything until now.
        rollController.onRollComplete = { [weak turnController] in
            turnController?.onStateChanged?()
        }
        // This is the step that makes renderer(_:updateAtTime:) actually
        // fire every frame — without it, settle detection never runs.
        sceneView.delegate = rollController

        let contactAudio = DiceContactAudio()
        contactAudio.playfieldHalfWidth = max(
            (layout.bounds.x.upperBound - layout.bounds.x.lowerBound) / 2, 0.001
        )
        scene.physicsWorld.contactDelegate = contactAudio
        lifecycle.onPoolReset = { [weak contactAudio] in contactAudio?.reset() }
        DiceAudioEngine.shared.start()

        let tapHandler = DiceTapHandler(
            sceneView: sceneView,
            turnController: turnController,
            rollController: rollController
        )

        return DiceGameSession(
            scene: scene,
            round: round,
            lifecycle: lifecycle,
            rollController: rollController,
            turnController: turnController,
            tapHandler: tapHandler,
            contactAudio: contactAudio
        )
    }
}
