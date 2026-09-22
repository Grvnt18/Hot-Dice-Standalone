import SwiftUI

// MARK: - Screen

struct FreeRollScreen: View {

    var onExit: (() -> Void)? = nil

    @State private var pool = FreeRollPool.default
    @State private var session: DiceTraySession?
    @State private var canRoll = false
    @State private var showingSettings = false
    @ObservedObject private var theme = AppTheme.shared

    var body: some View {
        GeometryReader { geo in
            // Same three-band split as DiceGameScreen, and for the same
            // reason: the scene is sized square because the playfield's
            // world bounds are derived from this view's measured aspect
            // ratio. The header is taller here than Rolls' 0.15 because the
            // picker needs two rows of chips, which still leaves the scene
            // square on a phone — the min() below gives up squareness only
            // on a screen too short for it, exactly as Rolls does.
            let headerHeight = geo.size.height * 0.26
            let minButtonHeight: CGFloat = 100
            let sceneHeight = min(geo.size.width, max(geo.size.height - headerHeight - minButtonHeight, 0))
            let buttonHeight = geo.size.height - headerHeight - sceneHeight

            VStack(spacing: 0) {
                picker
                    .frame(height: headerHeight)

                DiceTraySceneView(
                    session: $session,
                    makeInitialDice: { pool.makeDice() },
                    onSessionCreated: { newSession in
                        // Asks the session what is on the table rather than
                        // reading `pool`. This closure outlives the body
                        // evaluation that created it, so a captured @State
                        // value would be frozen at assembly time and go
                        // stale the moment the player changed the dice.
                        newSession.onStateChanged = { [weak newSession] in
                            guard let newSession else { return }
                            canRoll = !newSession.isRolling
                                && !newSession.lifecycle.rollableDice.isEmpty
                        }
                        canRoll = !newSession.lifecycle.rollableDice.isEmpty
                    }
                )
                .frame(height: sceneHeight)
                .background(Color.black)
                .overlay(alignment: .topLeading) {
                    if let onExit {
                        overlayButton(systemName: "chevron.left") {
                            onExit()
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    overlayButton(systemName: "gearshape.fill") {
                        showingSettings = true
                    }
                }

                DiceRollButton(
                    label: "Roll",
                    isEnabled: canRoll,
                    subtitle: pool.isEmpty ? "Add some dice first" : ""
                ) {
                    session?.roll()
                    canRoll = false
                }
                .frame(height: buttonHeight)
            }
        }
        .textCase(.uppercase)
        .dynamicTypeSize(.large)
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showingSettings) {
            SettingsView(gameName: FreeRollGame.displayName, rules: FreeRollGame.rules)
        }
        .onAppear {
            AppFonts.registerIfNeeded()
            SoundEngine.shared.startMusic()
        }
        // Repaints the floor in place when the table colour changes, so the
        // new shade shows the moment Settings closes rather than next launch.
        .onChange(of: theme.colorwayIndex) { _, _ in
            session?.applyTheme()
        }
    }

    // MARK: Picker

    private var picker: some View {
        ZStack {
            WoodTiledBackground()

            VStack(spacing: 6) {
                HStack {
                    Text("\(pool.total) / \(FreeRollPool.maxDice)")
                        .font(.stackSans(13))
                        .foregroundStyle(.white.opacity(0.85))

                    Spacer()

                    Button {
                        // No play(.buttonTap) here — applyPool() makes that
                        // sound, and doubling it was audibly a click-click.
                        pool.clear()
                        applyPool()
                    } label: {
                        Text("Clear")
                            .font(.stackSans(12))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Color.black.opacity(0.35),
                                in: RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                            )
                    }
                    .disabled(pool.isEmpty)
                    .opacity(pool.isEmpty ? 0.4 : 1)
                }
                .padding(.horizontal, 14)

                LazyVGrid(columns: chipColumns, spacing: 6) {
                    ForEach(FreeRollPool.availableSides, id: \.self) { sides in
                        DiceChip(
                            sides: sides,
                            count: pool.count(of: sides),
                            accent: theme.accentColor,
                            canAdd: !pool.isFull,
                            onAdd: {
                                pool.add(sides)
                                applyPool()
                            },
                            onRemove: {
                                pool.remove(sides)
                                applyPool()
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 8)
        }
    }

    private let chipColumns = Array(
        repeating: GridItem(.flexible(), spacing: 6),
        count: 3
    )

    /// Rebuilds the dice on the table to match the current selection.
    ///
    /// Ignored mid-roll — `DiceTraySession.setPool` guards on that too, but
    /// keeping the button state honest here avoids a moment where the UI
    /// says the pool changed and the table disagrees.
    private func applyPool() {
        SoundEngine.shared.play(.buttonTap)
        session?.setPool(pool.makeDice())
        canRoll = !(session?.isRolling ?? false) && !pool.isEmpty
    }

    private func overlayButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            SoundEngine.shared.play(.buttonTap)
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: systemName == "chevron.left" ? .semibold : .regular))
                .foregroundStyle(.white.opacity(0.75))
                .padding(9)
                .background(
                    Color.black.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                )
        }
        .padding(10)
    }
}

// MARK: - Chip

private struct DiceChip: View {
    let sides: Int
    let count: Int
    let accent: Color
    let canAdd: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onRemove) {
                stepperGlyph("minus")
            }
            .disabled(count == 0)
            .opacity(count == 0 ? 0.35 : 1)

            VStack(spacing: 0) {
                Text("d\(sides)")
                    .font(.stackSans(12))
                    .foregroundStyle(.white)
                Text("\(count)")
                    .font(.stackSans(15))
                    .foregroundStyle(.white.opacity(count == 0 ? 0.45 : 1))
            }
            .frame(maxWidth: .infinity)

            Button(action: onAdd) {
                stepperGlyph("plus")
            }
            .disabled(!canAdd)
            .opacity(canAdd ? 1 : 0.35)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                .fill(accent.opacity(count > 0 ? 0.9 : 0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ControlShape.cornerRadius)
                .stroke(.black.opacity(0.35), lineWidth: 1)
        )
    }

    private func stepperGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Color.black.opacity(0.3), in: Circle())
    }
}
