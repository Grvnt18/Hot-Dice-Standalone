import AVFoundation
import Combine

/// Every sound effect the game can trigger. Raw values are the bundle
/// resource base names — add matching audio files to Resources and they'll
/// be picked up automatically. See SoundEngine.preload() for the extensions
/// tried.
enum SFX: String, CaseIterable {
    case diceRoll      = "sfx_dice_roll"
    case diceSettle    = "sfx_dice_settle"
    case dieSelect     = "sfx_die_select"
    case dieDeselect   = "sfx_die_deselect"
    case bank          = "sfx_bank"
    case turnComplete  = "sfx_turn_complete"
    case buttonTap     = "sfx_button_tap"
}

/// Central audio controller: one looping music track plus fire-and-forget
/// sound effects, with independently persisted volume + mute for each.
///
/// Deliberately tolerant of missing files. No audio assets ship with this
/// package yet, so every play call no-ops silently if its file isn't in the
/// bundle — the game stays fully playable and the settings UI stays fully
/// functional while sounds are still being sourced. Drop files in later and
/// they start working with no code changes.
final class SoundEngine: ObservableObject {

    static let shared = SoundEngine()

    // MARK: Persisted settings

    @Published var musicEnabled: Bool {
        didSet {
            defaults.set(musicEnabled, forKey: Keys.musicEnabled)
            musicEnabled ? resumeMusic() : pauseMusic()
        }
    }

    @Published var musicVolume: Double {
        didSet {
            defaults.set(musicVolume, forKey: Keys.musicVolume)
            musicPlayer?.volume = Float(musicVolume)
        }
    }

    @Published var sfxEnabled: Bool {
        didSet { defaults.set(sfxEnabled, forKey: Keys.sfxEnabled) }
    }

    @Published var sfxVolume: Double {
        didSet { defaults.set(sfxVolume, forKey: Keys.sfxVolume) }
    }

    private enum Keys {
        static let musicEnabled = "audio.musicEnabled"
        static let musicVolume  = "audio.musicVolume"
        static let sfxEnabled   = "audio.sfxEnabled"
        static let sfxVolume    = "audio.sfxVolume"
        static let selectedTrack = "audio.selectedTrack"
    }

    private let defaults = UserDefaults.standard

    // MARK: Players

    private var musicPlayer: AVAudioPlayer?
    /// Preloaded SFX players, keyed by effect. Preloading matters here:
    /// creating an AVAudioPlayer does file I/O and decoding, which on the
    /// first play of each sound would stutter the physics simulation
    /// running every frame.
    private var sfxPlayers: [SFX: AVAudioPlayer] = [:]
    /// Overflow players for effects that can legitimately overlap (15 dice
    /// settling in quick succession). A single AVAudioPlayer restarts
    /// rather than layering, which would swallow all but the last hit.
    private var overflowPlayers: [AVAudioPlayer] = []
    private let maxOverflow = 8

    private init() {
        // register(defaults:) rather than reading raw — a missing key
        // returns false/0.0 from UserDefaults, which would silently start
        // every new install fully muted.
        defaults.register(defaults: [
            Keys.musicEnabled: true,
            Keys.musicVolume: 0.5,
            Keys.sfxEnabled: true,
            Keys.sfxVolume: 0.8,
            Keys.selectedTrack: -1
        ])
        musicEnabled = defaults.bool(forKey: Keys.musicEnabled)
        musicVolume  = defaults.double(forKey: Keys.musicVolume)
        sfxEnabled   = defaults.bool(forKey: Keys.sfxEnabled)
        sfxVolume    = defaults.double(forKey: Keys.sfxVolume)
        let stored = defaults.integer(forKey: Keys.selectedTrack)
        selectedTrackIndex = (stored >= 0 && stored < Self.tracks.count) ? stored : nil

        configureSession()
        preload()
    }

    /// .playback with mixWithOthers.
    ///
    /// Was .ambient, which is the "polite" category — but .ambient is
    /// SILENCED BY THE HARDWARE MUTE SWITCH, so on a muted iPad the game
    /// produced no sound at all with no indication why, and nothing in
    /// the in-app settings would show it. .playback ignores the mute
    /// switch, which is the correct behaviour for a game whose audio is
    /// part of the experience rather than incidental.
    ///
    /// mixWithOthers is kept, so this still never interrupts music the
    /// player already has going — the politeness that actually mattered
    /// is preserved.
    private func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: playback may still work, and the game must not
            // fail to start over audio setup.
            print("[SoundEngine] Audio session setup failed: \(error)")
        }

        // Without this, music silently stays paused forever after ANY
        // interruption (phone call, Siri, an alarm, another app briefly
        // taking audio focus) — the system pauses AVAudioPlayer for the
        // interruption's duration on our behalf, but nothing resumes it
        // afterward unless we ask. That's the actual cause of "music stops
        // after a long session and only comes back if you manually change
        // the track": a longer session just means more time for some
        // interruption to occur, and picking a track happens to force a
        // fresh startMusic() call via selectedTrackIndex's didSet.
        //
        // Closure-based addObserver, not the #selector API, since
        // SoundEngine doesn't inherit NSObject (see musicDelegate's own
        // comment on why the same is true there).
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // The system has already paused musicPlayer for us; nothing to
            // do until it ends.
            break
        case .ended:
            guard musicEnabled else { return }
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            // .shouldResume specifically means the system judges it's safe
            // to resume now (e.g. a phone call was declined rather than
            // answered) — resuming unconditionally would restart over
            // audio the system deliberately kept active elsewhere.
            guard AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("[SoundEngine] Failed to reactivate session after interruption: \(error)")
            }
            musicPlayer?.play()
        @unknown default:
            break
        }
    }

    private func preload() {
        for effect in SFX.allCases {
            guard let url = Self.url(forResource: effect.rawValue) else { continue }
            guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            sfxPlayers[effect] = player
        }
    }

    /// Tries the common formats rather than hardcoding one, so whichever
    /// you end up sourcing works without a code change.
    private static func url(forResource name: String) -> URL? {
        for ext in ["mp3", "m4a", "wav", "caf", "aiff"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    // MARK: Music

    /// Track base names, tried in bundle order. Discovered by probing, so
    /// adding or removing tracks is a matter of dropping files in.
    struct MusicTrack {
        let resource: String
        let displayName: String
    }

    /// Display names are deliberately unrelated to the filenames — the
    /// resource name is an implementation detail and "Baller_v1" isn't a
    /// title. Baked goods, per request.
    static let tracks: [MusicTrack] = [
        MusicTrack(resource: "music_baller", displayName: "Babka"),
        MusicTrack(resource: "music_speedrun", displayName: "Snickerdoodle")
    ]

    /// nil = shuffle through everything; otherwise lock to one track.
    @Published var selectedTrackIndex: Int? {
        didSet {
            defaults.set(selectedTrackIndex ?? -1, forKey: Keys.selectedTrack)
            // Switch immediately rather than waiting for the current track
            // to end — a selection that takes two minutes to take effect
            // reads as broken.
            musicPlayer?.stop()
            musicPlayer = nil
            musicBag.removeAll()
            startMusic()
        }
    }

    /// Shuffled playback order, consumed then reshuffled — same "bag"
    /// approach as the impact variants, so both tracks are heard before
    /// either repeats rather than one dominating by chance.
    private var musicBag: [Int] = []
    private var currentTrack: Int?

    /// Starts background music if it isn't already playing. Safe to call
    /// repeatedly.
    func startMusic() {
        if musicPlayer?.isPlaying == true { return }
        guard musicEnabled else { return }

        // Resume an existing paused track rather than restarting it, so
        // toggling music off and on doesn't jump back to the beginning.
        if let player = musicPlayer {
            player.play()
            return
        }
        playNextTrack()
    }

    private func playNextTrack() {
        guard musicEnabled else { return }
        var available = Self.tracks.indices.filter {
            Self.url(forResource: Self.tracks[$0].resource) != nil
        }
        // A locked selection narrows the pool to one, so the bag logic
        // below keeps working unchanged rather than needing a second path.
        if let pick = selectedTrackIndex, available.contains(pick) {
            available = [pick]
        }
        guard !available.isEmpty else {
            // Tells us whether the tracks are actually in the bundle,
            // which is otherwise indistinguishable from "playing silently".
            print("[SoundEngine] no music tracks found. Looked for: \(Self.tracks.map(\.resource))")
            return
        }

        if musicBag.isEmpty {
            var fresh = available.shuffled()
            // Don't let a reshuffle repeat the track that just finished.
            if available.count > 1, let last = currentTrack, fresh.first == last {
                fresh.swapAt(0, fresh.count - 1)
            }
            musicBag = fresh
        }

        let idx = musicBag.removeFirst()
        currentTrack = idx
        guard let url = Self.url(forResource: Self.tracks[idx].resource),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }

        // numberOfLoops = 0, not -1: each track plays once and then the
        // delegate advances to the next. Looping a single track forever
        // would mean only ever hearing whichever one started first.
        // Loop forever when locked to one track; otherwise play once and
        // let the delegate advance to the next.
        player.numberOfLoops = (selectedTrackIndex != nil) ? -1 : 0
        player.volume = Float(musicVolume)
        player.delegate = musicDelegate
        player.prepareToPlay()
        musicPlayer = player
        player.play()
        print("[SoundEngine] music: \(Self.tracks[idx].displayName) vol=\(musicVolume) playing=\(player.isPlaying)")
    }

    /// Advances to the next track when one finishes. Held as a separate
    /// object because AVAudioPlayer's delegate is weak and SoundEngine
    /// itself doesn't inherit NSObject.
    private lazy var musicDelegate: MusicAdvanceDelegate = {
        MusicAdvanceDelegate { [weak self] in self?.playNextTrack() }
    }()

    /// Halts music outright. Needed because the session uses .playback,
    /// which permits audio to keep running when the app isn't foreground —
    /// in Playgrounds that lets a track outlive the app it belongs to and
    /// appear to play independently of it. The app must therefore stop its
    /// own audio explicitly on lifecycle changes; nothing does it for us.
    func suspendForBackground() {
        musicPlayer?.pause()
    }

    func resumeFromForeground() {
        guard musicEnabled else { return }
        musicPlayer?.play()
    }

    private func resumeMusic() {
        guard musicPlayer != nil else {
            startMusic()
            return
        }
        musicPlayer?.play()
    }

    private func pauseMusic() {
        musicPlayer?.pause()
    }

    // MARK: SFX

    /// Fire-and-forget. `allowOverlap` lets rapid repeats layer instead of
    /// cutting each other off — appropriate for dice settling, not for UI
    /// clicks.
    func play(_ effect: SFX, allowOverlap: Bool = false) {
        guard sfxEnabled else { return }
        guard let base = sfxPlayers[effect] else { return }

        if allowOverlap, base.isPlaying {
            playOverlapping(url: base.url)
            return
        }

        base.volume = Float(sfxVolume)
        base.currentTime = 0
        base.play()
    }

    private func playOverlapping(url: URL?) {
        guard let url else { return }
        // Reuse a finished player before allocating a new one, and cap the
        // pool — 15 dice settling within a second shouldn't spawn unbounded
        // players.
        //
        // Previously this read overflowPlayers.count from inside its own
        // removeAll(where:) predicate, which is both confusing (the count
        // it sees isn't the count after removal) and an exclusive-access
        // hazard. Reuse alone is sufficient here: the pool is already
        // hard-capped below, so idle players are recycled rather than
        // needing periodic pruning.
        if let free = overflowPlayers.first(where: { !$0.isPlaying }) {
            free.volume = Float(sfxVolume)
            free.currentTime = 0
            free.play()
            return
        }

        guard overflowPlayers.count < maxOverflow,
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = Float(sfxVolume)
        player.prepareToPlay()
        player.play()
        overflowPlayers.append(player)
    }
}

/// Minimal AVAudioPlayerDelegate that just reports "finished".
final class MusicAdvanceDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag else { return }
        onFinish()
    }
}
