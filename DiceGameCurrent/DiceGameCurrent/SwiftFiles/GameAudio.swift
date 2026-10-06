import Foundation

/// The sample sets, by name.
///
/// One list, because a name typed twice is a sound that plays in one place
/// and not the other — and a missing set is silent, which is the hardest
/// kind of bug to notice. `tools_audio_verify.py` reads this and checks
/// every set against what is actually in `Resources`.
///
/// Numbered files are variants of one set and are played round-robin:
/// `sfx_bb_bat_01.wav` through `_07`. A set with no number is a single
/// sound.
enum AudioSet {

    // Baseball Dice
    static let swing   = "sfx_bb_swing"      // 4 variants
    static let bat     = "sfx_bb_bat"        // 7 variants
    static let glove   = "sfx_bb_glove"      // 6 variants
    static let baseballIntro = "sfx_bb_intro"

    // Rollbots
    static let blade   = "sfx_bot_blade"     // 3 variants
    static let pistol  = "sfx_bot_pistol"    // 8 variants
    static let cannon  = "sfx_bot_cannon"    // 3 variants
    static let overclock = "sfx_bot_overclock"
    static let virus     = "sfx_bot_virus"
    static let phase     = "sfx_bot_phase"
    static let repairWare = "sfx_bot_repair"

    // Three Thousand
    static let bust    = "sfx_3k_bust"        // 7 variants

    // Boneheads
    static let remove  = "sfx_bones_remove"   // 4 variants

    // Hog
    static let oink    = "sfx_hog_oink"       // 10 variants

    // Royal UR. Sliced out of one take by tools_sfx_slice.py — nine of the
    // ten onsets it found; the tenth was 20dB down on the rest and would
    // have been a silent move once every nine.
    static let urMove  = "sfx_ur_move"        // 9 variants

    // Freighter Yacht Dinghy — the sea, cycled for the whole session.
    static let wave    = "sfx_fyd_wave"       // 3 variants

    // The win screen. Two openers, three bodies that cycle under it.
    static let victoryStart = "sfx_victory_start"   // 2 variants
    static let victoryEnd   = "sfx_victory_end"     // 3 variants

    static let baseball = [swing, bat, glove, baseballIntro]
    static let rollbots = [blade, pistol, cannon,
                           overclock, virus, phase, repairWare]
    static let victory  = [victoryStart, victoryEnd]
}

// MARK: - Baseball Dice

/// What an at-bat sounds like.
///
/// **The whole sequence fires when the dice SETTLE**, not when they are
/// thrown. The outcome is not known until then — the dice are the pitch
/// and the swing — so a bat crack at the throw would either be a guess or
/// would give the result away two seconds early. Confirmed as the wanted
/// timing.
///
/// The shape of it is the play:
///
///     strikeout    swing, then the catcher's mitt
///     field out    swing, the bat, then the glove a beat later
///     deep out     swing, the bat, then the glove much later — the ball
///                  was up there a while
///     walk         the mitt alone. Ball four is the one at-bat where the
///                  batter never swung, so there is nothing to swing.
///     hits         swing and the bat, and nothing catches it
enum BaseballAudio {

    /// Between the swing and the bat meeting the ball. Short enough to
    /// read as one event.
    static let contactDelay: TimeInterval = 0.12

    /// Bat to glove on a routine out — caught off the infield.
    static let fieldOutCatch: TimeInterval = 0.45

    /// Bat to glove on a deep out. Long, because that is what says the
    /// ball was in the air rather than fielded off the bat.
    static let deepOutCatch: TimeInterval = 1.2

    /// Ball to mitt on a pitch nobody hit.
    static let missedPitch: TimeInterval = 0.25

    static func preload() {
        DiceAudioEngine.shared.preload(AudioSet.baseball)
    }

    /// Plays the at-bat. Call it the moment the result is known.
    static func play(_ result: AtBatResult) {
        let engine = DiceAudioEngine.shared

        // A walk has no swing in it at all.
        if result == .walk {
            engine.play(set: AudioSet.glove, gain: 0.8, jitter: false)
            return
        }

        engine.play(set: AudioSet.swing, gain: 0.9, jitter: false)

        switch result {
        case .strikeout:
            // Swing and a miss: the ball carries on into the mitt.
            engine.play(set: AudioSet.glove, gain: 0.85, jitter: false,
                        delay: missedPitch)

        case .fieldOut:
            engine.play(set: AudioSet.bat, gain: 0.85, jitter: false,
                        delay: contactDelay)
            engine.play(set: AudioSet.glove, gain: 0.8, jitter: false,
                        delay: contactDelay + fieldOutCatch)

        case .deepOut:
            engine.play(set: AudioSet.bat, gain: 1.0, jitter: false,
                        delay: contactDelay)
            engine.play(set: AudioSet.glove, gain: 0.8, jitter: false,
                        delay: contactDelay + deepOutCatch)

        case .single, .double, .triple:
            engine.play(set: AudioSet.bat, gain: 0.95, jitter: false,
                        delay: contactDelay)

        case .homeRun:
            engine.play(set: AudioSet.bat, gain: 1.0, jitter: false,
                        delay: contactDelay)

        case .walk:
            break                       // handled above
        }
    }

    /// The intro sting. Played twice in a match and no more: with the very
    /// first throw, and once on the result screen.
    static func playIntro() {
        DiceAudioEngine.shared.play(set: AudioSet.baseballIntro,
                                    gain: 1.0, jitter: false)
    }
}

// MARK: - Rollbots

/// What a Rollbots turn sounds like.
///
/// The weapon fires when the attack is THROWN rather than when it
/// resolves: the dice are the shot, and the defender's answer comes on
/// their own turn, seconds later. An ability sounds the moment it is
/// activated, for the same reason.
enum RollbotsAudio {

    static func preload() {
        DiceAudioEngine.shared.preload(AudioSet.rollbots)
    }

    /// The weapon being fired.
    ///
    /// The Sidearm takes the pistol's sound: it is the small gun you are
    /// left holding, and it is the only weapon with no sample of its own.
    static func fire(_ weapon: CyberWeapon) {
        let set: String
        switch weapon {
        case .monoBlade:   set = AudioSet.blade
        case .smartPistol: set = AudioSet.pistol
        case .railRifle:   set = AudioSet.cannon
        case .sidearm:     set = AudioSet.pistol
        }
        DiceAudioEngine.shared.play(set: set,
                                    gain: weapon == .sidearm ? 0.7 : 1.0,
                                    jitter: false)
    }

    static func activate(_ ware: Cyberware) {
        let set: String
        switch ware {
        case .neuralOverclock:     set = AudioSet.overclock
        case .corrosiveVirus:      set = AudioSet.virus
        case .quantumPhase:        set = AudioSet.phase
        case .emergencySubroutine: set = AudioSet.repairWare
        }
        DiceAudioEngine.shared.play(set: set, gain: 1.0, jitter: false)
    }
}

// MARK: - The sea, under Freighter Yacht Dinghy

/// A wave bed that runs for the whole session.
///
/// **Governed by the SFX volume and mute, not music** — so a player who
/// turns the music off still gets the sea, and the music track keeps
/// playing underneath untouched. That is the decision taken: the two beds
/// coexist rather than one replacing the other, and they answer to separate
/// controls because they are separate things.
///
/// Built on `DiceAudioEngine.play(set:...)` rather than a looping
/// `AVAudioPlayer` so it takes the round-robin for free: the three waves are
/// different lengths (5.07s, 1.59s, 4.75s), and a bed that cycled them in a
/// fixed order at a fixed period would audibly repeat. The next one is
/// scheduled slightly before the current finishes, so the sea never gaps.
@MainActor
enum SeaAudio {

    /// How far before the end of one wave the next begins. The waves have
    /// long tails, so this is an overlap rather than a crossfade — enough
    /// that the bed never falls silent, short enough not to stack up.
    static let overlap: TimeInterval = 0.6

    /// Shortest of the three, minus the overlap. Scheduling off the SHORTEST
    /// rather than each file's own length is what keeps this simple: the
    /// engine picks which variant plays, so the caller cannot know the
    /// duration of the one it is about to get.
    private static let period: TimeInterval = 1.59 - overlap

    /// Quiet. A bed that competes with the dice is not a bed.
    static let gain: Float = 0.35

    private static var running = false
    private static var generation = 0

    static func preload() {
        DiceAudioEngine.shared.preload([AudioSet.wave])
    }

    static func start() {
        guard !running else { return }
        running = true
        generation += 1
        schedule(generation)
    }

    /// Call on disappear. Easy to forget, and forgetting it leaves the sea
    /// playing over the hub — which is the specific bug this guards.
    static func stop() {
        running = false
        generation += 1
    }

    private static func schedule(_ token: Int) {
        guard running, token == generation else { return }
        DiceAudioEngine.shared.play(set: AudioSet.wave, gain: gain, jitter: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + period) {
            schedule(token)
        }
    }
}

// MARK: - Fireworks, on the win

/// One opener, then the bodies cycling under it until the screen goes away.
///
/// All five files are exactly 6.02s, which is what makes a fixed schedule
/// safe here where `SeaAudio` needs the shortest-file trick: every sound in
/// this set is the same length, so the next can be timed off a constant.
@MainActor
enum VictoryAudio {

    /// Overlap between one burst and the next. Generous, because fireworks
    /// that start cleanly one after another sound like a list; what is
    /// wanted is a sky that keeps going.
    static let overlap: TimeInterval = 1.5

    private static let length: TimeInterval = 6.02
    private static var running = false
    private static var generation = 0

    static func preload() {
        DiceAudioEngine.shared.preload(AudioSet.victory)
    }

    /// Fires once when the win screen appears.
    static func start() {
        guard !running else { return }
        running = true
        generation += 1
        let token = generation

        // One of the two openers, picked by the engine's own round-robin.
        DiceAudioEngine.shared.play(set: AudioSet.victoryStart, jitter: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + length - overlap) {
            cycle(token)
        }
    }

    static func stop() {
        running = false
        generation += 1
    }

    private static func cycle(_ token: Int) {
        guard running, token == generation else { return }
        DiceAudioEngine.shared.play(set: AudioSet.victoryEnd, jitter: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + length - overlap) {
            cycle(token)
        }
    }
}
