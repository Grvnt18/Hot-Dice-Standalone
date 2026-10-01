import SceneKit
import QuartzCore

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
    /// Re-renders the floor and "ROLLS" text from AppTheme's current
    /// selection. Call this whenever the player changes the color in
    /// Settings, so a game already on screen updates live instead of only
    /// on next launch.
    let applyTheme: () -> Void
}

/// A tray of dice you roll and read: no scoring, no banking, no selection,
/// so no DiceTurnController and no DiceTapHandler.
///
/// Free Roll was the first consumer but never the only intended one —
/// Jackpot, Freighter.Yacht.Dinghy, Generals and Three Thousand all want exactly this.
/// Rolls keeps its own DiceGameSession, which carries the turn controller,
/// tap selection and banking none of these games use.
///
/// A class rather than a struct because it owns mutable wiring and is
/// handed around by reference as the scene's lifetime anchor.
final class DiceTraySession {
    let scene: SCNScene
    let lifecycle: DicePoolLifecycleController
    let rollController: DiceRollController

    /// Retained for the same reason DiceGameSession retains it:
    /// SCNPhysicsWorld.contactDelegate is a WEAK reference, so without a
    /// strong reference living as long as the session this deallocates the
    /// moment assembly returns and no contact sounds ever play.
    let contactAudio: DiceContactAudio

    /// Needed on hand because re-picking the dice means calling
    /// setupPool again, which requires the bounds. DiceGameSession never
    /// exposed these — Rolls builds its pool once and never changes it.
    let playAreaBounds: (x: ClosedRange<Float>, z: ClosedRange<Float>)

    let applyTheme: () -> Void

    /// Fired when the Roll button's enabled state may have changed.
    var onStateChanged: (() -> Void)?

    /// Fired when the player taps a die and the selection changes.
    var onSelectionChanged: ((Set<UUID>) -> Void)?

    /// Whether taps select dice at all.
    ///
    /// Off by default: Free Roll, Jackpot and Freighter.Yacht.Dinghy all select
    /// nothing, and a die that pulses when brushed would be a bug in each
    /// of them. Generals turns it on for the part of a turn where keeping
    /// is a decision, and off again while the dice are in the air.
    var isSelectionEnabled = false {
        didSet { if !isSelectionEnabled { clearSelection() } }
    }

    /// Dice the player has tapped. In a keeping game these are the dice a
    /// reroll will leave alone — pass them straight to `roll(keeping:)`.
    private(set) var selectedIDs: Set<UUID> = []

    /// Selected dice that can no longer be un-selected.
    ///
    /// A subset of `selectedIDs`, so `roll(keeping: selectedIDs)` still
    /// keeps them. Three Thousand needs this: dice set aside on an earlier
    /// roll of the same turn are already scored, and without a lock a tap
    /// could put one back in the cup and score it twice.
    private(set) var lockedIDs: Set<UUID> = []

    /// Retained for the same reason `DiceGameSession` retains its own: the
    /// gesture recognizer holds its target weakly, so without a strong
    /// reference here taps would stop working the moment assembly returned.
    fileprivate(set) var tapHandler: DiceTapHandler?

    /// Fired once every die in a roll has settled, with each die's result.
    ///
    /// For a d4 the reported number is the face it came to REST on, not a
    /// reading — see DiceRollController's note. Interpret it with
    /// `DieFaceLabels.d4ApexValue(restingFace:)` for a top-read die or
    /// `.d4ExposedFaceNumbers(restingFace:)` for a face-numbered one.
    var onRollSettled: (([DieResult]) -> Void)?

    /// One die's outcome, with enough context to score it without going
    /// back to the scene graph.
    struct DieResult {
        let id: UUID
        let sides: Int
        /// Top face for most dice; resting face for a d4.
        let value: Int
    }

    /// Accumulates across a roll, then ships in one go via onRollSettled.
    /// Keyed by die so a duplicate settle callback cannot double-count.
    private var settledThisRoll: [UUID: DieResult] = [:]

    /// Every die's current face for the turn in progress, including dice
    /// that were kept rather than rethrown.
    ///
    /// Without this, a partial reroll would report only the dice that
    /// moved, so each keep would silently shrink the hand the game sees —
    /// which is the same class of failure Jackpot's "score only a
    /// complete set" guard exists to catch. Entries for the dice being
    /// thrown are dropped at the start of each roll, so a die that somehow
    /// never reports cannot leave a stale face behind. `beginTurn()`
    /// clears the lot.
    private var turnValues: [UUID: DieResult] = [:]

    var isRolling: Bool { rollController.isRolling }

    init(
        scene: SCNScene,
        lifecycle: DicePoolLifecycleController,
        rollController: DiceRollController,
        contactAudio: DiceContactAudio,
        playAreaBounds: (x: ClosedRange<Float>, z: ClosedRange<Float>),
        d4Style: DieFaceLabels.D4LabelStyle,
        applyTheme: @escaping () -> Void
    ) {
        self.scene = scene
        self.lifecycle = lifecycle
        self.rollController = rollController
        self.contactAudio = contactAudio
        self.playAreaBounds = playAreaBounds
        self.d4Style = d4Style
        self.applyTheme = applyTheme
    }

    /// The d4 labelling this tray was built with, so a re-pooled tray keeps
    /// the same style rather than silently reverting to the default.
    private let d4Style: DieFaceLabels.D4LabelStyle

    /// Toggles one die's kept state, if selection is on and the die has
    /// landed.
    func toggleSelection(dieID: UUID) {
        // Nothing on the table is selectable mid-throw. This replaces the
        // tap handler's own settled check, which cannot serve a keeping
        // game — see DiceTapHandler's note on requireSettled.
        guard isSelectionEnabled, !rollController.isRolling else { return }
        guard !lockedIDs.contains(dieID) else { return }
        guard let node = lifecycle.rollableDice.first(where: { $0.id == dieID })?.node else { return }
        let nowSelected = !selectedIDs.contains(dieID)
        if nowSelected {
            selectedIDs.insert(dieID)
        } else {
            selectedIDs.remove(dieID)
        }
        SoundEngine.shared.play(.buttonTap)
        DieSelectionHighlight.setSelected(nowSelected, on: node)
        onSelectionChanged?(selectedIDs)
    }

    /// Freezes the current selection: those dice keep sitting out every
    /// reroll, and a tap will no longer release them.
    ///
    /// Locking does not clear the selection — the locked dice stay in
    /// `selectedIDs` precisely so the next `roll(keeping: selectedIDs)`
    /// leaves them alone.
    func lockSelection() {
        lockedIDs.formUnion(selectedIDs)
        for die in lifecycle.rollableDice where lockedIDs.contains(die.id) {
            DieSelectionHighlight.setLocked(true, on: die.node)
        }
        onSelectionChanged?(selectedIDs)
    }

    /// Drops every selection and stops the highlights.
    ///
    /// Walks the whole pool rather than only `selectedIDs`, so a die left
    /// pulsing by any path — a re-pooled tray, a selection made before the
    /// dice were swapped — is put back to full opacity.
    func clearSelection() {
        selectedIDs.removeAll()
        lockedIDs.removeAll()
        for die in lifecycle.rollableDice {
            DieSelectionHighlight.setSelected(false, on: die.node)
        }
        onSelectionChanged?(selectedIDs)
    }

    /// Swaps in a different set of dice. setupPool already tears the
    /// previous pool down, so this is safe to call repeatedly.
    func setPool(_ dice: [Die]) {
        guard !rollController.isRolling else { return }
        settledThisRoll.removeAll()
        turnValues.removeAll()
        selectedIDs.removeAll()
        lockedIDs.removeAll()
        lifecycle.setupPool(
            dice,
            playAreaBounds: playAreaBounds,
            styleAsRolls: false,
            d4Style: d4Style
        )
        onStateChanged?()
    }

    /// Called per die as it settles; collected until the roll completes.
    fileprivate func recordSettled(id: UUID, value: Int) {
        guard let sides = lifecycle.rollableDice.first(where: { $0.id == id })?.sides else { return }
        settledThisRoll[id] = DieResult(id: id, sides: sides, value: value)
    }

    /// Called once the whole roll is done.
    fileprivate func finishRoll() {
        for (id, result) in settledThisRoll { turnValues[id] = result }
        settledThisRoll.removeAll()
        // Reported in the pool's own order rather than settle order, so a
        // game scoring "the d6 and the d20" does not depend on which die
        // happened to stop moving first. Kept dice are included at their
        // retained faces — see `turnValues`.
        let ordered = lifecycle.rollableDice.compactMap { turnValues[$0.id] }
        onStateChanged?()
        if !ordered.isEmpty { onRollSettled?(ordered) }
    }

    /// Forgets the faces retained from the previous turn.
    ///
    /// Only games that keep dice between rolls need to call this; a game
    /// that always throws everything drops each die's retained face as it
    /// rethrows it anyway.
    func beginTurn() {
        settledThisRoll.removeAll()
        turnValues.removeAll()
        clearSelection()
    }

    /// Throws every die again. Same two steps DiceTurnController.beginRoll
    /// uses — the impulse and then the settle tracking — minus the scoring.
    ///
    /// Returns false when nothing was thrown, which a caller that changes
    /// state around the roll has to respect. Jackpot flipped itself to a
    /// "rolling" phase and then called this; when it no-opped nothing ever
    /// moved the phase back, leaving the game permanently stuck with a
    /// disabled button.
    @discardableResult
    func roll() -> Bool {
        roll(keeping: [])
    }

    /// Throws every die except the ones named, which stay exactly as they
    /// are — both on the table and in the next `onRollSettled`.
    ///
    /// **A kept die cannot be knocked by a rethrown one.** A die that has
    /// settled is already `.kinematic` (see DiceRollController), and
    /// `DiceRollImpulse.launch` sets `.dynamic` only on the dice it is
    /// handed. Kinematic bodies ignore forces and collisions, so passing
    /// the un-kept dice alone is the whole of what keeping requires — no
    /// freezing, no moving dice aside.
    @discardableResult
    func roll(keeping keptIDs: Set<UUID>) -> Bool {
        guard !rollController.isRolling else { return false }
        let dice = lifecycle.rollableDice.filter { !keptIDs.contains($0.id) }
        guard !dice.isEmpty else { return false }
        SoundEngine.shared.play(.diceRoll)
        DiceRollImpulse.launch(dice: dice)
        settledThisRoll.removeAll()
        for die in dice { turnValues.removeValue(forKey: die.id) }
        rollController.startRoll(dice: dice, currentTime: CACurrentMediaTime())
        onStateChanged?()
        return true
    }
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
        into sceneView: SCNView,
        title: String = RollsGame.floorTitle
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

        let env = buildEnvironment(into: sceneView, title: title)
        let scene = env.scene
        let layout = env.layout
        let floorY = env.floorY
        let floorSurfaceMaterial = env.floorSurfaceMaterial
        let floorTextMaterial = env.floorTextMaterial
        let diceContainer = env.diceContainer

        let round = DiceGameRound()
        let lifecycle = DicePoolLifecycleController(containerNode: diceContainer)
        lifecycle.setupPool(round.pool, playAreaBounds: layout.bounds)

        let rollController = DiceRollController()
        // Containment safety net needs to agree with the colliders and
        // camera on where the playfield actually is.
        rollController.playAreaBounds = layout.bounds
        rollController.floorY = floorY
        rollController.ceilingY = floorY + PlayfieldVerticalBounds.ceilingHeight

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
            RollsTrace.log("rolls: onRollComplete -> onStateChanged")
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
            rollController: rollController,
            onDieTapped: { [weak turnController] dieID in
                turnController?.toggleSelection(dieID: dieID)
            }
        )

        return DiceGameSession(
            scene: scene,
            round: round,
            lifecycle: lifecycle,
            rollController: rollController,
            turnController: turnController,
            tapHandler: tapHandler,
            contactAudio: contactAudio,
            applyTheme: {
                DiceSceneEnvironment.applyTheme(
                    surfaceMaterial: floorSurfaceMaterial,
                    textMaterial: floorTextMaterial,
                    title: title
                )
            }
        )
    }

    // MARK: - Shared environment

    /// Camera, lighting, floor, walls, physics container and the node dice
    /// live under — everything both games need and neither varies.
    ///
    /// Extracted when Free Roll arrived. The alternative was a second copy
    /// of ~70 lines of ordering-sensitive setup, which would have drifted
    /// the first time either game's playfield was touched.
    private struct Environment {
        let scene: SCNScene
        let layout: PlayfieldLayout.Result
        let floorY: Float
        let floorSurfaceMaterial: SCNMaterial
        let floorTextMaterial: SCNMaterial
        let diceContainer: SCNNode
    }

    private static func buildEnvironment(
        into sceneView: SCNView,
        title: String,
        style: ArenaStyle = .house
    ) -> Environment {
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

        let floorSurfaceMaterial = DiceSceneEnvironment.addFloorSurface(
            to: scene.rootNode,
            bounds: layout.bounds,
            floorY: floorY,
            style: style
        )

        let floorTextMaterial = DiceSceneEnvironment.addFloorText(
            to: scene.rootNode,
            bounds: layout.bounds,
            floorY: floorY,
            title: title
        )

        // Visual height only — the actual containment boundary (in
        // DicePlayfieldPhysics.makeContainer below) is much taller and
        // invisible, guaranteeing dice can never physically escape
        // regardless of roll energy. This is sized to look like a
        // reasonable dice-tray rim relative to the playfield, not to
        // survive any particular bounce height.
        // Visible only. The containment boundary below is built either way,
        // so an arena with no rim still cannot lose a die.
        if style.showsWoodenRim {
            DiceSceneEnvironment.addWalls(
                to: scene.rootNode,
                bounds: layout.bounds,
                floorY: floorY,
                visualHeight: 10.4 // doubled again from 5.2 per request
            )
        }

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
        return Environment(
            scene: scene,
            layout: layout,
            floorY: floorY,
            floorSurfaceMaterial: floorSurfaceMaterial,
            floorTextMaterial: floorTextMaterial,
            diceContainer: diceContainer
        )
    }


    // MARK: - Dice tray

    /// Same playfield, no game on top of it.
    ///
    /// Call once sceneView has a real, non-zero size, exactly as with
    /// assemble(into:).
    static func assembleTray(
        into sceneView: SCNView,
        pool: [Die],
        d4Style: DieFaceLabels.D4LabelStyle = .topRead,
        title: String,
        style: ArenaStyle = .house
    ) -> DiceTraySession {
        AppFonts.registerIfNeeded()

        let env = buildEnvironment(into: sceneView, title: title, style: style)

        let lifecycle = DicePoolLifecycleController(containerNode: env.diceContainer)
        lifecycle.setupPool(
            pool,
            playAreaBounds: env.layout.bounds,
            styleAsRolls: false,
            d4Style: d4Style
        )

        let rollController = DiceRollController()
        rollController.playAreaBounds = env.layout.bounds
        rollController.floorY = env.floorY
        rollController.ceilingY = env.floorY + PlayfieldVerticalBounds.ceilingHeight

        // Without this the render loop never calls the roll controller and
        // settle detection never runs, so dice would tumble forever.
        sceneView.delegate = rollController

        let contactAudio = DiceContactAudio()
        contactAudio.playfieldHalfWidth = max(
            (env.layout.bounds.x.upperBound - env.layout.bounds.x.lowerBound) / 2, 0.001
        )
        env.scene.physicsWorld.contactDelegate = contactAudio
        lifecycle.onPoolReset = { [weak contactAudio] in contactAudio?.reset() }
        DiceAudioEngine.shared.start()

        let session = DiceTraySession(
            scene: env.scene,
            lifecycle: lifecycle,
            rollController: rollController,
            contactAudio: contactAudio,
            playAreaBounds: env.layout.bounds,
            d4Style: d4Style,
            applyTheme: {
                DiceSceneEnvironment.applyTheme(
                    style: style,
                    surfaceMaterial: env.floorSurfaceMaterial,
                    textMaterial: env.floorTextMaterial,
                    title: title
                )
            }
        )

        session.tapHandler = DiceTapHandler(
            sceneView: sceneView,
            rollController: rollController,
            requireSettled: false,
            onDieTapped: { [weak session] dieID in
                session?.toggleSelection(dieID: dieID)
            }
        )

        // Per-die results are collected as they land, then delivered in one
        // batch when the roll completes — a game wants the whole hand, not
        // a trickle, and the pair of callbacks below is already exactly
        // that shape.
        rollController.onDieSettled = { [weak session] dieID, _, value in
            session?.recordSettled(id: dieID, value: value)
        }
        rollController.onRollComplete = { [weak session] in
            session?.finishRoll()
        }

        return session
    }
}
