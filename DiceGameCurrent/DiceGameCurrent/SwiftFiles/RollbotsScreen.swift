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
        /// Accuracy die in the air.
        case rollingAccuracy
        /// Defender picks a reaction, with the accuracy already on the table.
        case defending
        /// Defence die in the air.
        case rollingDefence
        /// Damage die in the air.
        case rollingDamage
        /// Exchange resolved; waiting to hand over.
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
        case .defending, .rollingDefence, .rollingDamage: return defender
        default:                                      return attacker
        }
    }

    var body: some View {
        ZStack {
            NetGrid()

            GeometryReader { geo in
                let panelHeight = geo.size.height * 0.20
                let barHeight: CGFloat = phase == .setup ? 0 : 104
                let bodyHeight = max(geo.size.height - panelHeight - barHeight, 0)

                VStack(spacing: 0) {
                    NetStatusPanel(
                        state: state,
                        activeSeat: viewingSeat,
                        names: names,
                        subtitle: panelSubtitle
                    )
                    .frame(height: panelHeight)

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
                    ZStack {
                        tray

                        if phase == .setup {
                            menuBackdrop { setupView }
                        } else if phase == .action {
                            menuBackdrop { actionView }
                        } else if phase == .swapping {
                            menuBackdrop { swapView }
                        } else if phase == .defending {
                            menuBackdrop { defenceView }
                        }
                    }
                    .frame(height: bodyHeight)

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
            }
            .overlay(alignment: .topLeading) {
                if let onExit {
                    overlayButton("chevron.left") { onExit() }
                }
            }
            .overlay(alignment: .topTrailing) {
                overlayButton("gearshape.fill") { showingSettings = true }
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
            SettingsView(gameName: RollbotsGame.displayName, rules: RollbotsGame.rules)
        }
        .onAppear {
            AppFonts.registerIfNeeded()
            SoundEngine.shared.startMusic()
        }
    }

    // MARK: Tray

    /// Darkens the dice behind a menu so its cards stay readable, without
    /// unmounting the tray that owns the dice session.
    private func menuBackdrop<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        ZStack {
            NetArt.background.opacity(0.88)
            content()
        }
    }

    private var tray: some View {
        DiceTraySceneView(
            session: $session,
            makeInitialDice: { [NetArt.die(sides: RollbotsRules.accuracySides, seat: 0)] },
            floorTitle: RollbotsGame.floorTitle,
            onSessionCreated: { newSession in
                newSession.onRollSettled = { results in
                    settled(results)
                }
            }
        )
        .background(Color.black)
    }

    // MARK: Setup

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(names[setupSeat]) — choose your loadout")
                    .font(.stackSans(13))
                    .foregroundStyle(NetArt.seat(setupSeat))
                    .padding(.top, 4)

                Text("Weapon")
                    .font(.stackSans(11))
                    .foregroundStyle(NetArt.text.opacity(0.6))
                ForEach(CyberWeapon.selectable) { weapon in
                    NetCard(
                        title: weapon.displayName,
                        summary: weapon.tagline,
                        tint: NetArt.seat(setupSeat),
                        isSelected: pendingWeapon == weapon
                    ) { pendingWeapon = weapon }
                }

                Text("Cyberware")
                    .font(.stackSans(11))
                    .foregroundStyle(NetArt.text.opacity(0.6))
                    .padding(.top, 4)
                ForEach(Cyberware.allCases) { ware in
                    NetCard(
                        title: ware.displayName,
                        summary: ware.reward,
                        detail: "Strain: \(ware.strain)",
                        tint: NetArt.seat(setupSeat),
                        isSelected: pendingWare == ware
                    ) { pendingWare = ware }
                }

                Button {
                    SoundEngine.shared.play(.buttonTap)
                    confirmSetup()
                } label: {
                    Text(setupSeat == 0 ? "Lock In" : "Begin The Duel")
                        .font(.stackSans(15))
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
                    .font(.stackSans(13))
                    .foregroundStyle(NetArt.seat(attacker))
                    .padding(.top, 4)

                NetCard(
                    title: state.canFire(attacker) ? "Attack" : "Charge",
                    summary: state.canFire(attacker)
                        ? "Throw for accuracy with the \(weapon.displayName). They answer it."
                        : "The Rail Rifle needs a turn to spin up. You cannot fire until it has.",
                    tint: NetArt.seat(attacker)
                ) { beginAttack() }

                if !state.wareUsed[attacker] {
                    NetCard(
                        title: "Activate \(ware.displayName)",
                        summary: ware.reward,
                        detail: "Strain: \(ware.strain)",
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
                    .font(.stackSans(13))
                    .foregroundStyle(NetArt.seat(attacker))
                    .padding(.top, 4)

                Text("Switching costs your turn, and any held charge.")
                    .font(.stackSans(11))
                    .foregroundStyle(NetArt.text.opacity(0.7))

                ForEach(CyberWeapon.selectable) { weapon in
                    let isCurrent = weapon == state.weapon[attacker]
                    NetCard(
                        title: isCurrent ? "\(weapon.displayName) — equipped" : weapon.displayName,
                        summary: weapon.tagline,
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
                    .font(.stackSans(13))
                    .foregroundStyle(NetArt.seat(defender))
                    .padding(.top, 4)

                Text("\(state.activeWeapon(attacker).displayName) · accuracy \(accuracy)")
                    .font(.stackSans(16))
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
            phase = .defending
            handoverTo = defender
            return
        }
        if throwDice(sides: RollbotsRules.accuracySides, seat: attacker) {
            phase = .rollingAccuracy
        }
    }

    private func activateWare() {
        let seat = attacker
        let ware = state.ware[seat]
        state.wareUsed[seat] = true

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
            state.ip[seat] = min(RollbotsRules.startingIP, state.ip[seat] + Cyberware.repairAmount)
            state.sidearmTurns[seat] = Cyberware.sidearmTurns
            lastLine = "\(names[seat]) repaired \(Cyberware.repairAmount) IP — and is down to the Sidearm."
            finishTurn()
        case .corrosiveVirus:
            // The only ability with a roll of its own, so it gets the tray.
            // Armed before the throw, not after: settled() reads this flag,
            // and ordering the two the other way round is the kind of race
            // that only shows up on a fast device.
            pendingVirus = true
            if throwDice(sides: 6, seat: seat) {
                phase = .rollingDamage
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
            defenceRoll = nil
            state.exposed[defender] = false
            if throwDice(sides: state.activeWeapon(attacker).damageSides, seat: attacker) {
                phase = .rollingDamage
            }
            return
        }
        guard let sides = option.sides else { return }
        if throwDice(sides: sides, seat: defender) {
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
        case .rollingAccuracy:
            accuracy = value
            phase = .defending
            handoverTo = defender
        case .rollingDefence:
            defenceRoll = value
            if throwDice(sides: state.activeWeapon(attacker).damageSides, seat: attacker) {
                phase = .rollingDamage
            }
        case .rollingDamage:
            resolveExchange(damageRoll: value)
        default:
            break
        }
    }

    private func resolveExchange(damageRoll: Int) {
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
    private func throwDice(sides: Int, seat: Int) -> Bool {
        guard let session else { return false }
        session.beginTurn()
        session.setPool([NetArt.die(sides: sides, seat: seat)])
        return session.roll()
    }

    // MARK: Buttons

    private var primaryLabel: String {
        switch phase {
        case .action, .swapping: return "Choose Above"
        case .rollingAccuracy: return "Rolling Accuracy"
        case .defending:       return "Choose Above"
        case .rollingDefence:  return "Rolling Defence"
        case .rollingDamage:   return "Rolling Damage"
        case .resolved:        return "Continue"
        case .finished:        return "Done"
        case .setup:           return ""
        }
    }

    private var isPrimaryEnabled: Bool { phase == .resolved }

    private var barSubtitle: String {
        switch phase {
        case .action:    return "Pick a move"
        case .swapping:  return "Pick a weapon, or cancel"
        case .defending: return "Accuracy \(accuracy) is on the table — answer it"
        case .resolved:  return lastLine ?? ""
        default:         return ""
        }
    }

    private var panelSubtitle: String? {
        switch phase {
        case .setup, .swapping: return "Loadout"
        case .defending: return "\(state.activeWeapon(attacker).displayName) incoming"
        default:         return lastLine
        }
    }

    private func primaryAction() {
        guard phase == .resolved else { return }
        endExchange()
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
        defenceRoll = nil
        usedOverclock = false
        pendingVirus = false
        phase = .setup
    }

    private func overlayButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: systemName == "chevron.left" ? .semibold : .regular))
                .foregroundStyle(NetArt.text.opacity(0.75))
                .padding(9)
                .background(
                    Color.black.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                )
        }
        .padding(10)
    }
}
