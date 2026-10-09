import SwiftUI

struct RollbotsScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var match = TurnMatch.localTwoPlayer()
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
    private var names: [String] { [match.displayName(for: match.participants[0]),
                                   match.displayName(for: match.participants[1])] }

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
                // Setup has the longest list and no dice worth seeing yet,
                // so it takes the whole column; every other menu leaves the
                // top of the tray clear.
                .frame(height: geo.size.height * (phase == .setup ? 1.0 : 0.58))
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
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 14)
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
                    tint: NetArt.seat(attacker)
                ) { beginAttack() }

                if !state.wareUsed[attacker] {
                    NetCard(
                        title: "Activate \(ware.displayName)",
                        summary: ware.reward,
                        detail: "Strain: \(ware.strain)",
                        icon: ware.iconName,
                        tint: NetArt.warn
                    ) { activateWare() }
                }

                NetCard(
                    title: "Swap Loadout",
                    summary: "Spend the turn changing weapon. Any held charge is lost.",
                    tint: NetArt.text.opacity(0.8)
                ) { swapLoadout() }
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
                        isSelected: isCurrent
                    ) { completeSwap(to: weapon) }
                }

                NetCard(
                    title: "Cancel",
                    summary: "Go back without spending your turn.",
                    tint: NetArt.text.opacity(0.8)
                ) { phase = .action }
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
                        tint: NetArt.seat(defender)
                    ) { choose(option) }
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
        if r.evaded { return "Dodged it entirely." }
        if r.lockedDown { return "Hard Lockdown — the whole shot absorbed." }
        if r.damage == 0 { return "The Firewall swallowed it." }
        let crit = r.isCrit ? "Critical — " : ""
        return "\(crit)\(names[defender]) took \(r.damage)."
    }

    /// Holds the result on screen. The turn does not advance until the
    /// player presses Continue, so nobody hands over a device before
    /// reading what just happened to them.
    private func finishTurn() {
        if !state.defeated.isEmpty {
            phase = .finished
            return
        }
        phase = .resolved
    }

    /// Ticks anything burning, checks for a winner, hands over.
    private func endExchange() {
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

    private var primaryLabel: String {
        switch phase {
        case .action, .swapping: return "Choose Above"
        case .rollingAttack:   return "Rolling"
        case .readingAttack:   return "Send It"
        case .defending:       return "Choose Above"
        case .rollingDefence:  return "Rolling Defence"
        case .readingDefence:  return "Resolve"
        case .resolved:        return "Continue"
        case .finished:        return "Done"
        case .setup:           return ""
        }
    }

    /// The three phases where the button is the way forward: read your
    /// attack, read your defence, or end the exchange.
    private var isPrimaryEnabled: Bool {
        phase == .resolved || phase == .readingAttack || phase == .readingDefence
    }

    private var barSubtitle: String {
        switch phase {
        case .action:    return "Pick a move"
        case .swapping:  return "Pick a weapon, or cancel"
        case .readingAttack:
            return "Accuracy \(accuracy) · damage \(damageRoll) — send it when you have read them"
        case .defending:
            return "Accuracy \(accuracy), damage \(damageRoll) — answer it"
        case .readingDefence:
            return "\(defence.displayName) rolled \(defenceRoll.map(String.init) ?? "—")"
        case .resolved:  return lastLine ?? ""
        default:         return ""
        }
    }

    private func primaryAction() {
        switch phase {
        case .readingAttack:  sendAttack()
        case .readingDefence: resolveExchange()
        case .resolved:       endExchange()
        default:              break
        }
    }

    private func startNewMatch() {
        match = TurnMatch.localTwoPlayer()
        state = RollbotsState(weapons: [.monoBlade, .monoBlade],
                              ware: [.corrosiveVirus, .corrosiveVirus])
        setupSeat = 0
        pendingWeapon = nil
        pendingWare = nil
        lastLine = nil
        accuracy = 0
        damageRoll = 0
        defenceRoll = nil
        usedOverclock = false
        pendingVirus = false
        phase = .setup
    }

}
