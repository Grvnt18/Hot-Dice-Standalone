import SwiftUI

struct RollbotsScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var match = TurnMatch.passAndPlay()
    @State private var state = RollbotsState(
        weapons: [.monoBlade, .monoBlade],
        ware: [.corrosiveVirus, .corrosiveVirus]
    )
    @State private var session: DiceTraySession?
    @State private var phase: Phase = .setup
    @State private var setupSeat = 0
    @State private var pendingWeapon: CyberWeapon?
    @State private var pendingWare: Cyberware?

    /// The exchange in progress.
    @State private var accuracy = 0

    /// The damage die, thrown alongside the accuracy die rather than after
    /// the defence is chosen.
    ///
    /// The defender therefore sees it before choosing. Measured against the
    /// shipped resolve(), that is worth 0.02 IP an exchange to the Blade,
    /// 0.01 to the Pistol and nothing at all to the Rail — because Dodge
    /// loses P(fail) x damage while a Firewall loses damage - absorb, so
    /// which is better barely depends on the damage value. Under a point
    /// across a 16 IP match, so nothing is rebalanced for it.
    @State private var damageRoll = 0
    @State private var defence: CyberDefence = .firewall
    @State private var defenceRoll: Int?
    @State private var usedOverclock = false
    /// True while the d6 in the air is a Corrosive Virus activation check.
    @State private var pendingVirus = false

    /// The move the player has TAPPED but not yet confirmed.
    ///
    /// Every card on this screen used to fire the moment it was touched,
    /// so a mis-tap spent a turn — and on the defence menu it spent the
    /// only reaction you had. Choosing and committing are two gestures
    /// now: the card selects, the bar below does it, and the bar says
    /// which one it is about to do.
    @State private var pendingMove: PendingMove?

    private enum PendingMove: Equatable {
        case attack
        case ware
        case openSwap
        case swapTo(CyberWeapon)
        case cancelSwap
        case defend(CyberDefence)
    }

    @State private var lastLine: String?
    @State private var handoverTo: Int?
    @State private var showingSettings = false

    private enum Phase {
        /// Each runner picks a weapon and an ability.
        case setup
        /// Attacker chooses what to do with the turn.
        case action
        /// Attacker is picking which weapon to switch to.
        case swapping
        /// The attacker's two dice — accuracy and damage — in the air.
        case rollingAttack
        /// Both dice have settled and the attacker is reading them.
        ///
        /// The game stops here rather than moving on the moment the dice
        /// stop moving. A roll you did not get to look at might as well have
        /// been made for you.
        case readingAttack
        /// Defender picks a reaction, with both dice already on the table.
        case defending
        /// Defence die in the air.
        case rollingDefence
        /// The defence die has settled and the defender is reading it.
        case readingDefence
        /// Exchange resolved; waiting to send the turn on.
        case resolved
        /// Match decided.
        case finished
    }

    private var attacker: Int { match.activeIndex }
    private var defender: Int { 1 - match.activeIndex }
    private var names: [String] { match.seatNames() }

    /// Whoever is looking at the screen right now, which is not always the
    /// attacker — the defence is chosen by the other seat.
    private var viewingSeat: Int {
        switch phase {
        case .setup:                                  return setupSeat
        case .defending, .rollingDefence, .readingDefence: return defender
        default:                                      return attacker
        }
    }


    // MARK: Sending a turn

    /// This screen's turn, packed the way the Messages extension will send
    /// it — the bookkeeping and the game's own state together, which is
    /// what MatchPayload exists to say.
    var wireTurn: MatchPayload<RollbotsState> {
        MatchPayload(match: match, state: state)
    }

    /// Adopts a turn that arrived from another device.
    ///
    /// Phase is not carried: a phase is what THIS device is doing with the
    /// dice in front of it, and the sender's is meaningless here.
    ///
    /// `.action` rather than a roll state, because an arriving turn makes
    /// this seat the attacker and that is where an attacker starts. There
    /// is no half-finished exchange to resume: RollbotsState carries
    /// integrity, loadouts and which abilities are armed — all of which are
    /// true between exchanges, never during one.
    func adopt(_ incoming: MatchPayload<RollbotsState>) {
        match = incoming.match
        state = incoming.state
        phase = .action
    }

    var body: some View {
        ZStack {
            NetGrid()

            GeometryReader { geo in
                // Rails down both edges rather than a band across the top:
                // the stats cost almost no height there, and the whole
                // middle of the screen goes to the dice.
                //
                // The viewing seat is always on the left — your own numbers
                // stay where your thumb is, the same way Boneheads keeps
                // your own grid nearest you.
                // The floor came back down to 78 once the rails started
                // sizing their own text.
                //
                // It was raised to 92 to stop the weapon name collapsing,
                // which was the right fix for a rail with a FIXED 12pt
                // label. But at 92 the clamp floor wins on every phone —
                // 0.22 x 375 is 82.5 — so two rails took 184pt of a 375pt
                // screen, half of it, and the tray got what was left. The
                // labels are derived from this width now (NetSeatRail.label),
                // so the rail can be narrow and still legible, which is what
                // deriving it was for.
                let railWidth = min(max(geo.size.width * 0.22, 78), 128)
                let barHeight: CGFloat = phase == .setup ? 0 : 104
                let bodyHeight = max(geo.size.height - barHeight, 0)

                HStack(spacing: 0) {
                    NetSeatRail(
                        state: state,
                        seat: viewingSeat,
                        name: names[viewingSeat],
                        width: railWidth
                    )
                    .frame(width: railWidth)

                    VStack(spacing: 0) {
                    // The tray is mounted for the WHOLE match and every
                    // menu is drawn over it, rather than the two swapping
                    // places.
                    //
                    // This was the bug behind "only Swap Loadout works".
                    // With the tray unmounted during .action, `session` was
                    // nil, so every action that throws dice — Attack, and
                    // the Corrosive Virus — bailed out of throwDice() and
                    // silently did nothing, while the actions that throw no
                    // dice worked fine. It also rebuilt the whole SceneKit
                    // scene on every single throw.
                    // Menus sit over the LOWER part of the tray, not all
                    // of it. The defence menu is why: the whole point of
                    // throwing the accuracy die before the defender
                    // chooses is that they can see it, and a full-screen
                    // backdrop hid the very die they were reading.
                    ZStack(alignment: .bottom) {
                        tray

                        if phase == .setup {
                            menuSheet { setupView }
                        } else if phase == .action {
                            menuSheet { actionView }
                        } else if phase == .swapping {
                            menuSheet { swapView }
                        } else if phase == .defending {
                            menuSheet { defenceView }
                        }
                    }
                    .frame(height: bodyHeight)
                    .overlay(alignment: .topLeading) {
                        if let onExit {
                            OverlayChromeButton(systemName: "chevron.left", tint: NetArt.text) { onExit() }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        OverlayChromeButton(systemName: "gearshape.fill", tint: NetArt.text) { showingSettings = true }
                    }

                    if phase != .setup {
                        NetActionBar(
                            primaryLabel: primaryLabel,
                            primaryEnabled: isPrimaryEnabled,
                            subtitle: barSubtitle,
                            tint: NetArt.seat(viewingSeat),
                            onPrimary: { primaryAction() }
                        )
                        .frame(height: barHeight)
                    }
                    }

                    NetSeatRail(
                        state: state,
                        seat: 1 - viewingSeat,
                        name: names[1 - viewingSeat],
                        width: railWidth
                    )
                    .frame(width: railWidth)
                }
            }

            if let handoverTo {
                NetHandoverGate(
                    nextName: names[handoverTo],
                    nextSeat: handoverTo,
                    summary: lastLine
                ) {
                    self.handoverTo = nil
                }
                .transition(.opacity)
            }

            if phase == .finished {
                NetResultView(
                    state: state,
                    names: names,
                    winners: winners,
                    onPlayAgain: { startNewMatch() },
                    onExit: { onExit?() }
                )
                .transition(.opacity)
            }
        }
        .textCase(.uppercase)
        .dynamicTypeSize(.large)
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showingSettings) {
            SettingsView(for: RollbotsGame.self)
        }
        .onAppear {
            AppFonts.registerIfNeeded()
            SoundEngine.shared.startMusic()
            // Decoded when the duel opens rather than on the first shot.
            RollbotsAudio.preload()
        }
    }

    // MARK: Tray

    /// Darkens the dice behind a menu so its cards stay readable, without
    /// unmounting the tray that owns the dice session.
    private func menuSheet<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        // Built here, NOT inside the GeometryReader. GeometryReader stores
        // its closure and re-runs it on every layout pass, so that closure
        // escapes — and a plain (non-@escaping) parameter may not be
        // captured by one. Swift rejects the build outright.
        //
        // Materialising the view once is the better of the two fixes: a
        // View is a value, so nothing has to retain a closure, and the
        // builder stops re-running on every resize. Named `menu` rather
        // than `body` on purpose — a `body` inside a View has bitten this
        // codebase before.
        let menu = content()
        return GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    // The same plate the arena rim is made of, tiled at the
                    // same fraction — so this panel and the rim it butts
                    // against read as one piece of metal, exactly the way
                    // the wooden games' header and tray do. The dark wash
                    // over it is what keeps the cards readable; without it
                    // the plate's own highlights compete with the text.
                    SteelTiledBackground()
                    NetArt.background.opacity(0.80)
                    menu
                }
                // CHOOSING takes the whole column; READING leaves the
                // tray clear.
                //
                // Setup, the action menu and the weapon picker are all
                // "pick one of these" and there is nothing on the table
                // worth seeing behind them — at setup no dice have been
                // thrown, and on your own turn the dice from the last
                // exchange are spent. The defence menu is the exception
                // and the reason this is not simply 1.0: the whole point
                // of throwing the accuracy die BEFORE the defender
                // chooses is that they can see it, and a full-height
                // panel hides the die they are answering.
                .frame(height: geo.size.height * (phase == .defending ? 0.58 : 1.0))
                .overlay(alignment: .top) {
                    Rectangle().fill(NetArt.line.opacity(0.4)).frame(height: 1)
                }
            }
        }
    }

    private var tray: some View {
        DiceTraySceneView(
            session: $session,
            makeInitialDice: { [NetArt.die(sides: RollbotsRules.accuracySides, seat: 0)] },
            floorTitle: RollbotsGame.floorTitle,
            // Brushed steel, no timber. The wooden tray is the wrong object
            // for a duel in the net, and it was the last thing on this
            // screen still reading as every other game.
            arenaStyle: .steel,
            onSessionCreated: { newSession in
                // One die at a time, and the number on it decides the
                // exchange — so every throw gets the largest size rather
                // than a random one. There is no handful here for the
                // variance to make look thrown.
                newSession.alwaysLargestDice = true
                newSession.onRollSettled = { results in
                    settled(results)
                }
            }
        )
        // Plate, not timber: this arena's rim is steel by design.
        .rollingWell(material: .plate)
    }

    // MARK: Setup

    private var setupView: some View {
        // The button is OUTSIDE the ScrollView.
        //
        // It was the last item in the list, so on a phone it sat below
        // the fold behind two sets of cards — you chose a weapon and an
        // ability and then had to scroll to find the way forward, with
        // nothing on screen saying there was one. Pinned here it is
        // always visible, and greyed until both choices are made so it
        // also says what is still missing.
        VStack(spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(names[setupSeat]) — choose your loadout")
                    .font(.poppins(13))
                    .foregroundStyle(NetArt.seat(setupSeat))
                    .padding(.top, 4)

                Text("Weapon")
                    .font(.poppins(13))
                    .foregroundStyle(NetArt.text.opacity(0.6))
                ForEach(CyberWeapon.selectable) { weapon in
                    NetCard(
                        title: weapon.displayName,
                        summary: weapon.tagline,
                        icon: weapon.iconName,
                        tint: NetArt.seat(setupSeat),
                        isSelected: pendingWeapon == weapon
                    ) { pendingWeapon = weapon }
                }

                Text("Cyberware")
                    .font(.poppins(13))
                    .foregroundStyle(NetArt.text.opacity(0.6))
                    .padding(.top, 4)
                ForEach(Cyberware.allCases) { ware in
                    NetCard(
                        title: ware.displayName,
                        summary: ware.reward,
                        detail: "Strain: \(ware.strain)",
                        icon: ware.iconName,
                        tint: NetArt.seat(setupSeat),
                        isSelected: pendingWare == ware
                    ) { pendingWare = ware }
                }

            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            }

            Button {
                SoundEngine.shared.play(.buttonTap)
                confirmSetup()
            } label: {
                Text(setupSeat == 0 ? "Lock In" : "Begin The Duel")
                    .font(.poppins(15))
                    .foregroundStyle(NetArt.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                            .fill(canConfirmSetup
                                  ? NetArt.seat(setupSeat)
                                  : NetArt.text.opacity(0.25))
                    )
            }
            .disabled(!canConfirmSetup)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var canConfirmSetup: Bool { pendingWeapon != nil && pendingWare != nil }

    private func confirmSetup() {
        guard let weapon = pendingWeapon, let ware = pendingWare else { return }
        state.weapon[setupSeat] = weapon
        state.ware[setupSeat] = ware
        pendingWeapon = nil
        pendingWare = nil

        if setupSeat == 0 {
            setupSeat = 1
            handoverTo = 1
            lastLine = nil
        } else {
            phase = .action
            handoverTo = 0
        }
    }

    // MARK: Action

    private var actionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let weapon = state.activeWeapon(attacker)
                let ware = state.ware[attacker]

                Text("\(names[attacker]) — your move")
                    .font(.poppins(13))
                    .foregroundStyle(NetArt.seat(attacker))
                    .padding(.top, 4)

                NetCard(
                    title: state.canFire(attacker) ? "Attack" : "Charge",
                    summary: state.canFire(attacker)
                        ? "Throw for accuracy with the \(weapon.displayName). They answer it."
                        : "The Rail Rifle needs a turn to spin up. You cannot fire until it has.",
                    icon: weapon.iconName,
                    tint: NetArt.seat(attacker),
                    isSelected: pendingMove == .attack
                ) { pendingMove = .attack }

                if !state.wareUsed[attacker] {
                    NetCard(
                        title: "Activate \(ware.displayName)",
                        summary: ware.reward,
                        detail: "Strain: \(ware.strain)",
                        icon: ware.iconName,
                        tint: NetArt.warn,
                        isSelected: pendingMove == .ware
                    ) { pendingMove = .ware }
                }

                NetCard(
                    title: "Swap Loadout",
                    summary: "Spend the turn changing weapon. Any held charge is lost.",
                    tint: NetArt.text.opacity(0.8),
                    isSelected: pendingMove == .openSwap
                ) { pendingMove = .openSwap }
            }
            .padding(.horizontal, 14)
        }
    }

    // MARK: Swapping

    private var swapView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(names[attacker]) — switch weapon")
                    .font(.poppins(13))
                    .foregroundStyle(NetArt.seat(attacker))
                    .padding(.top, 4)

                Text("Switching costs your turn, and any held charge.")
                    .font(.poppins(13))
                    .foregroundStyle(NetArt.text.opacity(0.7))

                ForEach(CyberWeapon.selectable) { weapon in
                    let isCurrent = weapon == state.weapon[attacker]
                    NetCard(
                        title: isCurrent ? "\(weapon.displayName) — equipped" : weapon.displayName,
                        summary: weapon.tagline,
                        icon: weapon.iconName,
                        tint: isCurrent ? NetArt.text.opacity(0.6) : NetArt.seat(attacker),
                        isSelected: pendingMove == .swapTo(weapon)
                    ) { pendingMove = .swapTo(weapon) }
                }

                NetCard(
                    title: "Cancel",
                    summary: "Go back without spending your turn.",
                    tint: NetArt.text.opacity(0.8),
                    isSelected: pendingMove == .cancelSwap
                ) { pendingMove = .cancelSwap }
            }
            .padding(.horizontal, 14)
        }
    }

    // MARK: Defence

    private var defenceView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(names[defender]) — incoming")
                    .font(.poppins(13))
                    .foregroundStyle(NetArt.seat(defender))
                    .padding(.top, 4)

                Text("\(state.activeWeapon(attacker).displayName) · accuracy \(accuracy)")
                    .font(.poppins(16))
                    .foregroundStyle(NetArt.warn)

                ForEach(state.defences(for: defender)) { option in
                    NetCard(
                        title: option.displayName,
                        summary: description(for: option),
                        tint: NetArt.seat(defender),
                        // Greyed, not removed. A card that vanishes
                        // teaches nothing; one that is there and greyed
                        // says "this exists, and not against this".
                        isSelected: pendingMove == .defend(option),
                        isEnabled: canHelp(option)
                    ) { pendingMove = .defend(option) }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    /// Says what each reaction is actually worth against *this* accuracy
    /// roll — which is the whole reason the roll is shown first.
    private func description(for option: CyberDefence) -> String {
        switch option {
        case .dodge:
            let outs = max(0, 6 - accuracy)
            return outs == 0
                ? "A d6 cannot beat \(accuracy). You would take all of it."
                : "Roll a d6 above \(accuracy) — \(outs) of 6 — and take nothing. Otherwise take all of it."
        case .firewall:
            // The card used to promise "a natural 8 stops everything"
            // unconditionally, which against a piercing shot is simply
            // untrue — resolve returns the raw damage before a natural 8
            // is ever looked at. Saying so is the point of greying it.
            guard canHelp(.firewall) else {
                return "The \(state.activeWeapon(attacker).displayName) "
                     + "goes straight through a Firewall. Nothing to roll."
            }
            return "Roll a d8 and subtract it from the damage. A natural 8 stops everything."
        case .phase:
            let outs = max(0, 12 - accuracy)
            return "Roll a d12 above \(accuracy) — \(outs) of 12 — for nothing taken and 4 back. Miss and it hits double."
        case .exposed:
            return "The Overclock left you wide open. You take this one in full."
        }
    }

    // MARK: Turn flow

    private func beginAttack() {
        guard state.canFire(attacker) else {
            state.charged[attacker] = true
            lastLine = "\(names[attacker]) spun up the Rail Rifle."
            finishTurn()
            return
        }
        usedOverclock = state.overclocked[attacker]
        if usedOverclock {
            // Forced to the top of the die; nothing is thrown for it.
            accuracy = RollbotsRules.overclockAccuracy
            // Accuracy is fixed at maximum, so only the damage die is thrown
            // — and it is still read before the handover.
            if throwDice(sides: [state.activeWeapon(attacker).damageSides],
                         seat: attacker) {
                RollbotsAudio.fire(state.activeWeapon(attacker))
                phase = .rollingAttack
            }
            handoverTo = defender
            return
        }
        // Both dice at once: the attacker sees the whole shot before it is
        // spent, instead of learning the damage after the defender has
        // already answered.
        if throwDice(sides: [RollbotsRules.accuracySides,
                             state.activeWeapon(attacker).damageSides],
                     seat: attacker) {
            // The dice ARE the shot, so the weapon sounds when they are
            // thrown rather than when the defender answers a turn later.
            RollbotsAudio.fire(state.activeWeapon(attacker))
            phase = .rollingAttack
        }
    }

    private func activateWare() {
        let seat = attacker
        let ware = state.ware[seat]
        state.wareUsed[seat] = true
        // Each ability has its own sound, and it plays on activation —
        // including the Virus, whose d6 is thrown a moment later to see
        // whether it turns on you.
        RollbotsAudio.activate(ware)

        switch ware {
        case .neuralOverclock:
            state.overclocked[seat] = true
            lastLine = "\(names[seat]) overclocked. Their next shot cannot be walled."
            finishTurn()
        case .quantumPhase:
            state.phaseArmed[seat] = true
            lastLine = "\(names[seat]) armed a Quantum Phase."
            finishTurn()
        case .emergencySubroutine:
            state.ip[seat] = min(RollbotsState.startingIP(seat), state.ip[seat] + Cyberware.repairAmount)
            state.sidearmTurns[seat] = Cyberware.sidearmTurns
            lastLine = "\(names[seat]) repaired \(Cyberware.repairAmount) IP — and is down to the Sidearm."
            finishTurn()
        case .corrosiveVirus:
            // The only ability with a roll of its own, so it gets the tray.
            // Armed before the throw, not after: settled() reads this flag,
            // and ordering the two the other way round is the kind of race
            // that only shows up on a fast device.
            pendingVirus = true
            if throwDice(sides: [6], seat: seat) {
                phase = .rollingAttack
            } else {
                pendingVirus = false
                state.wareUsed[seat] = false
            }
        }
    }

    /// Opens the picker rather than swapping on the spot.
    ///
    /// It used to cycle blindly to the next weapon in the list, so you
    /// could not choose and could not see what you were getting.
    private func swapLoadout() {
        phase = .swapping
    }

    private func completeSwap(to weapon: CyberWeapon) {
        let seat = attacker
        guard weapon != state.weapon[seat] else {
            // Picking what you already hold is a change of mind, not a
            // turn — spending one by mis-tapping a menu is the worst way
            // to lose a turn.
            phase = .action
            return
        }
        state.weapon[seat] = weapon
        state.charged[seat] = false
        lastLine = "\(names[seat]) switched to the \(weapon.displayName)."
        finishTurn()
    }

    /// Whether this reaction can change the outcome of the shot on the
    /// table.
    ///
    /// `state.defences(for:)` answers what the seat's own state allows,
    /// which is a different question: against a Rail Rifle it still offers
    /// a Firewall, and the card promises "a natural 8 stops everything",
    /// which against that weapon is untrue. See RollbotsRules.canHelp.
    private func canHelp(_ option: CyberDefence) -> Bool {
        RollbotsRules.canHelp(option,
                              weapon: state.activeWeapon(attacker),
                              accuracy: accuracy,
                              // usedOverclock, not state.overclocked:
                              // resolveExchange passes that one, and the
                              // flag is cleared during resolution. Two
                              // different values here would mean canHelp
                              // answering about a different shot than the
                              // one that lands.
                              ignoresFirewall: usedOverclock)
    }

    /// True when nothing the defender could pick would change the number.
    ///
    /// The Rail Rifle at accuracy 6 or more, and the Exposed state — which
    /// turns out to have been the same case all along.
    private var noDefenceCanHelp: Bool {
        !state.defences(for: defender).contains { canHelp($0) }
    }

    private func choose(_ option: CyberDefence) {
        defence = option
        if option == .phase { state.phaseArmed[defender] = false }
        if option == .exposed {
            // Nothing to throw: the attacker cannot be answered this turn,
            // and their damage die is already on the table.
            defenceRoll = nil
            state.exposed[defender] = false
            resolveExchange()
            return
        }
        guard let sides = option.sides else { return }
        if throwDice(sides: [sides], seat: defender) {
            phase = .rollingDefence
        }
    }

    private func settled(_ results: [DiceTraySession.DieResult]) {
        guard let value = results.first?.value else { return }

        if pendingVirus {
            pendingVirus = false
            let seat = attacker
            if value >= Cyberware.virusActivatesOn {
                state.virusTurns[defender] = Cyberware.virusTurns
                lastLine = "Virus took hold — \(names[defender]) burns for \(Cyberware.virusDamagePerTurn) a turn."
            } else {
                state.virusTurns[seat] = Cyberware.virusTurns
                lastLine = "Feedback! The virus turned on \(names[seat])."
            }
            finishTurn()
            return
        }

        switch phase {
        case .rollingAttack:
            // Overclock fixes the accuracy, so only read a d10 if one was
            // actually thrown.
            if let acc = self.value(of: RollbotsRules.accuracySides, in: results) {
                accuracy = acc
            }
            damageRoll = self.value(of: state.activeWeapon(attacker).damageSides,
                                    in: results) ?? value
            phase = .readingAttack
        case .rollingDefence:
            defenceRoll = value
            phase = .readingDefence
        default:
            break
        }
    }

    /// The attacker has read their two dice and sends the shot across.
    private func sendAttack() {
        // No defence die at all when none of them could change the
        // number. Handing the device over to pick between three greyed
        // cards is a decision that does not exist, and the old flow made
        // the defender throw a d8 and read a result that was already
        // fixed. The banner names the weapon nothing stops.
        //
        // This is the Rail Rifle at accuracy 6 or more, and the Exposed
        // state — which turns out to have been the same case all along.
        if noDefenceCanHelp {
            defence = .exposed
            defenceRoll = nil
            // Consumed if it was set; a no-op in the Rail case, where it
            // was never set in the first place.
            state.exposed[defender] = false
            resolveExchange()
            return
        }
        phase = .defending
        handoverTo = defender
    }

    private func resolveExchange() {
        let weapon = state.activeWeapon(attacker)
        let resolution = RollbotsRules.resolve(
            weapon: weapon,
            accuracy: accuracy,
            damageRoll: damageRoll,
            defence: defence,
            defenceRoll: defenceRoll,
            ignoresFirewall: usedOverclock
        )

        state.ip[defender] -= resolution.damage
        state.ip[attacker] -= resolution.counter

        if weapon.needsCharge { state.charged[attacker] = false }
        if usedOverclock {
            state.overclocked[attacker] = false
            // The strain lands on their turn, in front of the opponent.
            state.exposed[attacker] = true
            usedOverclock = false
        }

        lastLine = line(for: resolution, weapon: weapon)
        finishTurn()
    }

    private func line(for r: RollbotsRules.Resolution, weapon: CyberWeapon) -> String {
        if r.evaded && r.counter > 0 {
            return "Phased clean through — and hit back for \(r.counter)."
        }
        if r.evaded { return "Dodged!" }
        if r.lockedDown || r.damage == 0 { return "Fully Absorbed!" }
        let crit = r.isCrit ? "Critical — " : ""
        return "\(crit)\(names[defender]) took \(r.damage)."
    }

    /// Holds the result on screen. The turn does not advance until the
    /// player presses Continue, so nobody hands over a device before
    /// reading what just happened to them.
    private func finishTurn() {
        pendingMove = nil
        if !state.defeated.isEmpty {
            phase = .finished
            return
        }
        phase = .resolved
    }

    /// Ticks anything burning, checks for a winner, hands over.
    private func endExchange() {
        pendingMove = nil
        match.advanceTurn()
        let next = match.activeIndex

        if state.virusTurns[next] > 0 {
            state.ip[next] -= Cyberware.virusDamagePerTurn
            state.virusTurns[next] -= 1
            lastLine = (lastLine.map { $0 + " " } ?? "")
                + "Virus burns \(names[next]) for \(Cyberware.virusDamagePerTurn)."
        }
        if state.sidearmTurns[next] > 0 { state.sidearmTurns[next] -= 1 }

        if !state.defeated.isEmpty {
            phase = .finished
            return
        }

        phase = .action
        handoverTo = next
    }

    private var winners: [Int] {
        let down = state.defeated
        if down.count == 2 || down.isEmpty { return [] }
        return [1 - down[0]]
    }

    // MARK: Dice

    /// Puts exactly one die on the table and throws it.
    ///
    /// One die per throw is what makes the tray readable without labels:
    /// the accuracy d10, the defence die and the damage die never share a
    /// table, so whatever is rolling is unambiguous.
    /// Returns false when nothing was thrown, which every caller has to
    /// respect: no throw means no settle callback, and a phase that moved
    /// first would be a phase nothing could move back. Jackpot shipped
    /// that bug once already.
    @discardableResult
    private func throwDice(sides: [Int], seat: Int) -> Bool {
        guard let session else { return false }
        session.beginTurn()
        session.setPool(sides.map { NetArt.die(sides: $0, seat: seat) })
        return session.roll()
    }

    /// Pulls one die out of a settled throw by its type.
    ///
    /// This is why the attack can throw two dice at once with no labels on
    /// them: the d10 is always accuracy and nothing else in the game uses
    /// one, and the other die is whatever the weapon rolls. The player
    /// reads them the same way the code does.
    private func value(of sides: Int, in results: [DiceTraySession.DieResult]) -> Int? {
        results.first { $0.sides == sides }?.value
    }

    // MARK: Buttons

    /// The bar says what pressing it will DO.
    ///
    /// In the choosing phases that is whichever card is selected — the
    /// bar reads "Attack", "Overclock", "Dodge" — and before anything is
    /// selected it asks for a choice. The two reading phases name the act
    /// the dice have already decided.
    private var primaryLabel: String {
        if let pendingMove { return label(for: pendingMove) }
        switch phase {
        // Each choosing phase names what it wants, rather than pointing
        // at the menu. "Choose Above" was the one label in the suite that
        // described where to look instead of what to do — and the menu it
        // pointed at covers the whole tray now, so "above" was also the
        // only thing on screen.
        //
        // Title case, like every other label on this bar and unlike
        // `barSubtitle` below: the labels name an action, the subtitles
        // are sentences.
        case .action:    return "Pick a Move"
        case .swapping:  return "Pick a Weapon"
        case .defending: return "Pick a Defence"
        case .rollingAttack:   return "Rolling"
        case .readingAttack:   return "Attack"
        case .rollingDefence:  return "Rolling Defence"
        case .readingDefence:  return defenceOutcomeLabel
        case .resolved:        return "Continue"
        case .finished:        return "Done"
        case .setup:           return ""
        }
    }

    private func label(for move: PendingMove) -> String {
        switch move {
        case .attack:          return state.canFire(attacker) ? "Attack" : "Charge"
        case .ware:            return state.ware[attacker].barLabel
        case .openSwap:        return "Swap"
        case .swapTo(let weapon):
            return weapon == state.weapon[attacker] ? "Keep It" : weapon.displayName
        case .cancelSwap:      return "Cancel"
        case .defend(let option): return option.barLabel
        }
    }

    /// What the defence die just decided, on the button that resolves it.
    ///
    /// The number is on the table and the outcome follows from it, so the
    /// bar says the outcome rather than "Resolve". `RollbotsRules.resolve`
    /// takes every input as an argument and returns a value, so asking it
    /// now and again a moment later cannot disagree.
    private var defenceOutcomeLabel: String {
        let preview = RollbotsRules.resolve(
            weapon: state.activeWeapon(attacker),
            accuracy: accuracy,
            damageRoll: damageRoll,
            defence: defence,
            defenceRoll: defenceRoll,
            ignoresFirewall: usedOverclock
        )
        if preview.evaded { return "Dodged!" }
        if preview.lockedDown || preview.damage == 0 { return "Fully Absorbed!" }
        return "Attack Lands"
    }

    /// Enabled when there is something to confirm: a selected card, a
    /// roll that has been read, or a resolution to send on.
    private var isPrimaryEnabled: Bool {
        if pendingMove != nil { return true }
        return phase == .resolved || phase == .readingAttack
            || phase == .readingDefence
    }

    private var barSubtitle: String {
        switch phase {
        case .action:    return "Pick a move"
        case .swapping:  return "Pick a weapon, or cancel"
        case .readingAttack:
            return "You attack for \(damageRoll) damage with \(accuracy) accuracy"
        case .defending:
            return "Accuracy \(accuracy), damage \(damageRoll) — answer it"
        case .readingDefence:
            return "\(defence.displayName) rolled \(defenceRoll.map(String.init) ?? "—")"
        case .resolved:  return lastLine ?? ""
        default:         return ""
        }
    }

    private func primaryAction() {
        // A selected card is what the bar is about to do; the phase only
        // decides when there is nothing selected.
        if let move = pendingMove {
            pendingMove = nil
            perform(move)
            return
        }
        switch phase {
        case .readingAttack:  sendAttack()
        case .readingDefence: resolveExchange()
        case .resolved:       endExchange()
        default:              break
        }
    }

    private func perform(_ move: PendingMove) {
        switch move {
        case .attack:             beginAttack()
        case .ware:               activateWare()
        case .openSwap:           swapLoadout()
        case .swapTo(let weapon): completeSwap(to: weapon)
        case .cancelSwap:         phase = .action
        case .defend(let option): choose(option)
        }
    }

    private func startNewMatch() {
        match = TurnMatch.passAndPlay()
        state = RollbotsState(weapons: [.monoBlade, .monoBlade],
                              ware: [.corrosiveVirus, .corrosiveVirus])
        setupSeat = 0
        pendingWeapon = nil
        pendingWare = nil
        pendingMove = nil
        lastLine = nil
        accuracy = 0
        damageRoll = 0
        defenceRoll = nil
        usedOverclock = false
        pendingVirus = false
        phase = .setup
    }

}
