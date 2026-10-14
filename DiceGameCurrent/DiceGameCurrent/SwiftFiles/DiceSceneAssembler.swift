import SceneKit
import QuartzCore

/// The parts of an assembled arena that outlive a refit.
///
/// A reference type on purpose, and the reason the whole refit works: the
/// sessions, the theme closures and the two screens that install their own
/// furniture all hold THIS, not the materials and bounds it happens to
/// carry today. A refit swaps what is inside and every holder is current,
/// where a struct would leave each of them pointing at an arena that is no
/// longer in the scene.
final class ArenaHandles {

    /// The node every piece of the arena hangs off, so a refit is a swap
    /// rather than a hunt through the scene graph.
    static let nodeName = "arenaEnvironment"

    /// The playfield as the walls, the camera and the containment box
    /// currently have it.
    private(set) var layout: PlayfieldLayout.Result
    private(set) var floorY: Float
    private(set) var surfaceMaterial: SCNMaterial
    private(set) var textMaterial: SCNMaterial

    /// The view shape this arena was built for, which is what decides
    /// whether a refit is needed at all.
    private(set) var aspect: Float

    var bounds: (x: ClosedRange<Float>, z: ClosedRange<Float>) { layout.bounds }

    init(layout: PlayfieldLayout.Result, floorY: Float,
         surfaceMaterial: SCNMaterial, textMaterial: SCNMaterial,
         aspect: Float) {
        self.layout = layout
        self.floorY = floorY
        self.surfaceMaterial = surfaceMaterial
        self.textMaterial = textMaterial
        self.aspect = aspect
    }

    /// Takes on a freshly built arena's handles, keeping this object's
    /// identity so everything holding it follows.
    func adopt(_ other: ArenaHandles) {
        layout = other.layout
        floorY = other.floorY
        surfaceMaterial = other.surfaceMaterial
        textMaterial = other.textMaterial
        aspect = other.aspect
    }
}

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
    /// The arena this session's dice are standing in, which a refit
    /// replaces under them. Held so the view can refit without going back
    /// through assembly, and so `applyTheme` paints the floor that is
    /// actually on screen rather than the one assembly first built.
    let arena: ArenaHandles
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

    /// The arena the dice are standing in. See `DiceGameSession.arena`.
    let arena: ArenaHandles

    /// Needed on hand because re-picking the dice means calling
    /// setupPool again, which requires the bounds. DiceGameSession never
    /// exposed these — Rolls builds its pool once and never changes it.
    ///
    /// Read through the arena rather than stored, because a refit moves
    /// them: a stored copy would re-pool a tray into the playfield the
    /// window used to have.
    var playAreaBounds: (x: ClosedRange<Float>, z: ClosedRange<Float>) {
        arena.bounds
    }

    /// Fired after the arena has been re-fitted to a view that changed
    /// shape.
    ///
    /// For the screens that put their own furniture on the playfield —
    /// Baseball Dice's runner posts and scoreboard — which are built
    /// against the bounds and so have to be rebuilt against the new ones.
    /// Nothing else needs it: the dice, the rim and the floor are the
    /// arena's own business.
    var onArenaResized: (() -> Void)?

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

    /// Dice the player has tapped.
    ///
    /// What a tap MEANS is the game's business, not this class's. In a
    /// keeping game — Three Thousand, Generals — these are the dice a
    /// reroll will leave alone, and they go straight to `roll(keeping:)`.
    /// In a rethrowing one — Rolls, and Freighter.Yacht.Dinghy's cargo —
    /// they are the dice the player has picked to throw AGAIN, and the
    /// game passes `roll(keeping: everything - selectedIDs)`.
    ///
    /// Both read the same on screen and that is the point: the pulse marks
    /// the dice the next button press will act on.
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
        arena: ArenaHandles,
        d4Style: DieFaceLabels.D4LabelStyle,
        applyTheme: @escaping () -> Void
    ) {
        self.scene = scene
        self.lifecycle = lifecycle
        self.rollController = rollController
        self.contactAudio = contactAudio
        self.arena = arena
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

    /// Locks exactly these dice, selecting nothing.
    ///
    /// `lockSelection()` freezes whatever the player has already picked,
    /// which suits a keeping game. A rethrowing one needs the opposite: the
    /// dice that are NOT the choice have to be set aside and made
    /// untappable before the player picks anything at all —
    /// Freighter.Yacht.Dinghy's three claimed vessels are not cargo and a
    /// tap on one must do nothing.
    ///
    /// Replaces any previous lock rather than adding to it, so re-entering
    /// the decision after a rethrow states the whole set again instead of
    /// accumulating.
    func lockOnly(_ ids: Set<UUID>) {
        lockedIDs = ids
        for die in lifecycle.rollableDice {
            if ids.contains(die.id) {
                DieSelectionHighlight.setLocked(true, on: die.node)
                selectedIDs.remove(die.id)
            } else if !selectedIDs.contains(die.id) {
                // Back to full opacity: a die that was locked a moment ago
                // and is cargo now must not stay dimmed.
                DieSelectionHighlight.setLocked(false, on: die.node)
            }
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
        title: String = RollsGame.floorTitle,
        seed: UInt64 = SeededGenerator.newSeed()
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
        let diceContainer = env.diceContainer

        // Seeded, so a Rolls match in a conversation deals every
        // participant the same fifteen dice: which colorway gets which
        // type, and in what order, is built entirely from this number, and
        // `RollsPlayerResult` travels as indices into that dealt order.
        // Defaults to a fresh seed, so the app is unchanged.
        let round = DiceGameRound(seed: seed)
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
            applyTheme: { [arena = env.arena] in
                // Through the handles, so a theme change after a refit
                // paints the floor that is on screen rather than the one
                // assembly built and the refit replaced.
                DiceSceneEnvironment.applyTheme(
                    surfaceMaterial: arena.surfaceMaterial,
                    textMaterial: arena.textMaterial,
                    title: title
                )
            },
            arena: env.arena
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
        let diceContainer: SCNNode
        /// The floor's materials live on this, not beside it: a refit
        /// replaces them, and a second copy out here would be the pair
        /// assembly built rather than the pair on screen.
        let arena: ArenaHandles
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

        DicePhysicsWorldConfigurator.configure(scene.physicsWorld)

        let arena = buildArena(into: sceneView, scene: scene, floorY: floorY,
                               title: title, style: style)

        // Dice live under their own container node rather than directly on
        // the scene root — keeps the scene graph organized and gives
        // DicePoolLifecycleController one clear parent to add/remove from.
        //
        // It is also what makes a refit possible: the arena hangs off its
        // OWN node, so re-fitting the playfield to a view that changed
        // shape swaps that one node and never touches this one or the dice
        // standing in it.
        let diceContainer = SCNNode()
        diceContainer.name = diceContainerName
        scene.rootNode.addChildNode(diceContainer)
        return Environment(
            scene: scene,
            layout: arena.layout,
            floorY: floorY,
            diceContainer: diceContainer,
            arena: arena
        )
    }

    static let diceContainerName = "diceContainer"

    /// Builds the arena — camera, lights, floor, mark, rim and the
    /// containment box — under one node, and hands back the handles
    /// anything outside it has to keep up with.
    ///
    /// ONE builder, called by assembly and by `refit` both, because the
    /// two agreeing matters more than either being readable on its own: a
    /// refit that built a slightly different arena would be a playfield
    /// whose walls and camera disagree, which is exactly the fault it
    /// exists to fix.
    @discardableResult
    private static func buildArena(into sceneView: SCNView,
                                   scene: SCNScene,
                                   floorY: Float,
                                   title: String,
                                   style: ArenaStyle) -> ArenaHandles {
        let aspectRatio = Float(sceneView.bounds.width
                                / max(sceneView.bounds.height, 1))
        let layout = PlayfieldLayout.compute(screenAspectRatio: aspectRatio)

        let arenaNode = SCNNode()
        arenaNode.name = ArenaHandles.nodeName

        let cameraNode = DiceCameraFactory.makeTopDownCamera(
            playfieldBounds: layout.bounds,
            orthographicScale: layout.orthographicScale,
            floorY: floorY
        )
        arenaNode.addChildNode(cameraNode)

        DiceSceneEnvironment.addLighting(
            to: arenaNode,
            playfieldBounds: layout.bounds,
            floorY: floorY
        )

        let surfaceMaterial = DiceSceneEnvironment.addFloorSurface(
            to: arenaNode,
            bounds: layout.bounds,
            floorY: floorY,
            style: style
        )

        let textMaterial = DiceSceneEnvironment.addFloorText(
            to: arenaNode,
            bounds: layout.bounds,
            floorY: floorY,
            title: title,
            mark: style.floorMark
        )

        // Visual height only — the actual containment boundary (in
        // DicePlayfieldPhysics.makeContainer below) is much taller and
        // invisible, guaranteeing dice can never physically escape
        // regardless of roll energy. This is sized to look like a
        // reasonable dice-tray rim relative to the playfield, not to
        // survive any particular bounce height.
        // Visible only. The containment boundary below is built either way,
        // so an arena with no rim still cannot lose a die.
        if style.rim != .none {
            DiceSceneEnvironment.addWalls(
                to: arenaNode,
                bounds: layout.bounds,
                floorY: floorY,
                visualHeight: 10.4, // doubled again from 5.2 per request
                material: style.rim
            )
        }

        arenaNode.addChildNode(
            DicePlayfieldPhysics.makeContainer(bounds: layout.bounds,
                                               floorY: floorY)
        )

        scene.rootNode.addChildNode(arenaNode)
        // After the node is in the scene: a point of view SceneKit cannot
        // find in the graph it is rendering is a black view.
        sceneView.pointOfView = cameraNode

        return ArenaHandles(layout: layout,
                            floorY: floorY,
                            surfaceMaterial: surfaceMaterial,
                            textMaterial: textMaterial,
                            aspect: aspectRatio)
    }

    // MARK: - Refitting

    /// Re-fits a Rolls arena, and tells the controllers where the walls
    /// went.
    ///
    /// The bounds reach three places that keep their own copy: the roll
    /// controller's containment net, the turn controller's (which re-pools
    /// at the start of a new game) and the contact audio's panning. All
    /// three take the new ones here, because a copy left behind is a net
    /// that catches dice at the old edge.
    static func refit(_ session: DiceGameSession, in sceneView: SCNView,
                      title: String = RollsGame.floorTitle,
                      style: ArenaStyle = .house) {
        guard refit(scene: session.scene, in: sceneView, arena: session.arena,
                    title: title, style: style) else { return }
        adoptBounds(session.arena, rollController: session.rollController,
                    contactAudio: session.contactAudio)
        session.turnController.playAreaBounds = session.arena.bounds
    }

    /// The same for a tray, plus the hook its screen may have left.
    static func refit(_ session: DiceTraySession, in sceneView: SCNView,
                      title: String, style: ArenaStyle) {
        guard refit(scene: session.scene, in: sceneView, arena: session.arena,
                    title: title, style: style) else { return }
        adoptBounds(session.arena, rollController: session.rollController,
                    contactAudio: session.contactAudio)
        session.onArenaResized?()
    }

    private static func adoptBounds(_ arena: ArenaHandles,
                                    rollController: DiceRollController,
                                    contactAudio: DiceContactAudio) {
        rollController.playAreaBounds = arena.bounds
        rollController.floorY = arena.floorY
        rollController.ceilingY = arena.floorY + PlayfieldVerticalBounds.ceilingHeight
        contactAudio.playfieldHalfWidth = max(
            (arena.bounds.x.upperBound - arena.bounds.x.lowerBound) / 2, 0.001
        )
    }

    /// Re-fits an assembled arena to a view that has changed shape,
    /// WITHOUT re-dealing.
    ///
    /// The playfield's world bounds come from the view's aspect ratio
    /// (`PlayfieldLayout.compute`), so a window that changes shape leaves
    /// the walls, the camera and the containment box built for a shape
    /// that is gone. The old answer was to assemble the whole scene again,
    /// which also tore down the dice pool — on an iPad, dragging a Split
    /// View divider mid-round threw the round away.
    ///
    /// This rebuilds the arena node alone. The dice container is a sibling
    /// and is not touched, so every die keeps its position, its face and
    /// its physics body; the only thing that moves a die is the clamp
    /// below, and only when the playfield got smaller underneath it.
    ///
    /// Returns false when the view has no size yet, so a caller can tell
    /// "not now" from "done".
    @discardableResult
    static func refit(scene: SCNScene,
                      in sceneView: SCNView,
                      arena: ArenaHandles,
                      title: String,
                      style: ArenaStyle) -> Bool {
        guard sceneView.bounds.width > 0, sceneView.bounds.height > 0 else {
            return false
        }

        scene.rootNode.childNode(withName: ArenaHandles.nodeName,
                                 recursively: false)?.removeFromParentNode()

        let rebuilt = buildArena(into: sceneView, scene: scene,
                                 floorY: arena.floorY,
                                 title: title, style: style)
        arena.adopt(rebuilt)

        clampDice(in: scene, to: rebuilt.bounds)
        return true
    }

    /// Pulls any die that the new, smaller playfield left outside its own
    /// walls back inside them.
    ///
    /// Only the depth can change — `PlayfieldLayout` holds the world WIDTH
    /// at a constant and derives depth from the aspect — so in practice
    /// this is a die near the top or bottom edge of a tray that just got
    /// shorter. Without it that die is on the wrong side of a wall that
    /// did not exist a frame ago, and the physics solver resolves that by
    /// throwing it.
    private static func clampDice(in scene: SCNScene,
                                  to bounds: (x: ClosedRange<Float>,
                                              z: ClosedRange<Float>)) {
        guard let container = scene.rootNode.childNode(withName: diceContainerName,
                                                       recursively: false) else { return }
        // A die's own half-extent, near enough: the pool normalises to 1.0
        // and the largest a round carries is 1.5, so this keeps the widest
        // of them clear of the wall rather than touching it.
        let inset: Float = 0.9
        let x = (bounds.x.lowerBound + inset)...(bounds.x.upperBound - inset)
        let z = (bounds.z.lowerBound + inset)...(bounds.z.upperBound - inset)
        guard x.lowerBound < x.upperBound, z.lowerBound < z.upperBound else { return }

        for die in container.childNodes {
            let position = die.presentation.position
            let clamped = SCNVector3(min(max(position.x, x.lowerBound), x.upperBound),
                                     position.y,
                                     min(max(position.z, z.lowerBound), z.upperBound))
            guard clamped.x != position.x || clamped.z != position.z else { continue }
            die.position = clamped
            // The body carries its own copy of the transform, and a
            // velocity pointing at the wall it was just moved off.
            die.physicsBody?.resetTransform()
            die.physicsBody?.velocity = SCNVector3Zero
            die.physicsBody?.angularVelocity = SCNVector4Zero
        }
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
            arena: env.arena,
            d4Style: d4Style,
            applyTheme: { [arena = env.arena] in
                DiceSceneEnvironment.applyTheme(
                    style: style,
                    surfaceMaterial: arena.surfaceMaterial,
                    textMaterial: arena.textMaterial,
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
