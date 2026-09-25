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

    static let baseball = [swing, bat, glove, baseballIntro]
    static let rollbots = [blade, pistol, cannon,
                           overclock, virus, phase, repairWare]
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
