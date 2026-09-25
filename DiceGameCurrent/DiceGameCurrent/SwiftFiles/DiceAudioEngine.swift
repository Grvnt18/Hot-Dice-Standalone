import AVFoundation
import Foundation

/// Impact velocity tiers. Raw values match the sample filename convention
/// (`sfx_impact_<tier>_NN.wav`), so adding variants is a matter of dropping
/// files in — no code change. The same is true of every other sample set
/// the engine plays: see `AudioSet`.
enum ImpactTier: String, CaseIterable {
    case soft, medium, hard
}

/// Low-latency, polyphonic playback for dice impact sounds.
///
/// Separate from SoundEngine on purpose. SoundEngine uses AVAudioPlayer,
/// which is right for a single looping music track but wrong for this:
/// it can't pitch-shift, and it allocates per-instance, so rapid-fire
/// impacts would both repeat audibly and churn memory. AVAudioEngine with
/// a fixed voice pool solves all three — preloaded PCM buffers (no file
/// I/O at play time), per-voice varispeed for pitch variation, and
/// per-voice pan for positional audio.
///
/// Settings (enabled / volume) still live in SoundEngine so there's one
/// source of truth backing the settings UI; this reads them at play time.
final class DiceAudioEngine {

    static let shared = DiceAudioEngine()

    // MARK: Tuning

    /// Simultaneous impact voices. Fifteen dice can contact in a tight
    /// cluster; beyond this many overlapping hits the result is mush
    /// anyway, so extra voices would cost CPU for no audible gain.
    private let voiceCount = 16

    /// Playback-rate jitter per hit. Varispeed shifts pitch and duration
    /// together, the way a genuinely different impact would differ. This
    /// is what stops a 10-variant round-robin from ever sounding looped —
    /// it multiplies the effective sample count enormously for free.
    private let pitchJitter: ClosedRange<Float> = 0.94...1.07

    // MARK: Engine

    private let engine = AVAudioEngine()
    private var voices: [(player: AVAudioPlayerNode, speed: AVAudioUnitVarispeed?)] = []
    private var graphFormat: AVAudioFormat?
    private var nextVoice = 0

    /// Preloaded buffers per SAMPLE SET, keyed by the set's resource base
    /// name — `sfx_impact_hard`, `sfx_bb_bat`, `sfx_bot_cannon`.
    ///
    /// It used to be keyed by `ImpactTier`, which was right while the dice
    /// were the only thing making a noise. Baseball Dice and Rollbots have
    /// their own sets now and want exactly what the impacts already had:
    /// round-robin without repeats, pitch jitter, and a voice pool that
    /// can overlap. A string key gives them all three without a second
    /// engine.
    private var buffers: [String: [AVAudioPCMBuffer]] = [:]

    /// Shuffled play order per set, consumed then reshuffled — a "bag".
    /// True random would repeat the same variant back-to-back roughly
    /// 1-in-N of the time, which the ear catches immediately; a bag
    /// guarantees every variant plays once before any repeats.
    private var bags: [String: [Int]] = [:]

    private var isRunning = false

    /// Serializes playback state. SCNPhysicsContactDelegate callbacks
    /// arrive on the physics thread, not the main thread, so the bag
    /// indices, voice cursor and last-played map were being mutated
    /// concurrently — a data race that can corrupt state or crash.
    private let audioQueue = DispatchQueue(label: "dice.audio", qos: .userInitiated)

    private init() {
        // Deliberately does NO audio work. Building the graph here meant
        // the very first `DiceAudioEngine.shared` access — during scene
        // assembly — could hard-crash the app at startup. See start().
    }

    // MARK: Setup

    /// Loads one set's samples, if they are not already in.
    ///
    /// A set is either numbered variants — `sfx_bb_bat_01.wav`,
    /// `_02`, … — or a single file under the bare name. Numbered first,
    /// stopping at the first gap, so the variant count is discovered from
    /// what is actually bundled rather than declared anywhere.
    ///
    /// Both spellings try `wav` then `mp3`: the sliced effects ship as
    /// WAV, and the few long one-shots (the Baseball intro, the Rollbots
    /// abilities) stay MP3 because at two to four seconds each the file
    /// size is worth more than the decode.
    private func loadSet(_ name: String) {
        guard buffers[name] == nil else { return }

        var loaded: [AVAudioPCMBuffer] = []
        for n in 1...99 {
            guard let buf = buffer(named: String(format: "%@_%02d", name, n)) else { break }
            loaded.append(buf)
        }
        if loaded.isEmpty, let single = buffer(named: name) {
            loaded.append(single)
        }
        // Converted here when the graph already knows its format, and by
        // buildGraph otherwise — a set can be asked for before or after
        // the engine starts.
        if let format = graphFormat {
            loaded = loaded.compactMap { convert($0, to: format) }
        }
        buffers[name] = loaded
        bags[name] = []
    }

    private func buffer(named name: String) -> AVAudioPCMBuffer? {
        for ext in ["wav", "mp3", "m4a"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext),
                  let file = try? AVAudioFile(forReading: url),
                  let buf = AVAudioPCMBuffer(
                      pcmFormat: file.processingFormat,
                      frameCapacity: AVAudioFrameCount(file.length)
                  ),
                  (try? file.read(into: buf)) != nil
            else { continue }
            return buf
        }
        return nil
    }

    /// Decodes sets ahead of the first time they are wanted.
    ///
    /// A game calls this when its screen opens, so the first swing of a
    /// match is not also the first file read. Sets are loaded on demand
    /// anyway — this only moves the cost off the moment it would be heard.
    func preload(_ names: [String]) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            for name in names { self.loadSet(name) }
        }
    }

    /// Converts a loaded buffer to `format`, so every buffer in the graph
    /// shares one stream format.
    ///
    /// This is the fix for CoreAudio -10868 (kAudioUnitErr_FormatNotSupported)
    /// at engine start. The samples are mono 44100, and they were being
    /// fed straight into AVAudioUnitVarispeed. Varispeed is a time-effect
    /// unit, and those expect the standard float32 format at the hardware
    /// sample rate — mono, or a rate that disagrees with the hardware, and
    /// it refuses the whole output chain. Passing nil to the mixer
    /// connection didn't rescue it; the engine won't insert a converter
    /// across a time effect.
    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }

    /// Builds the voice graph at a single canonical format.
    ///
    /// `useVarispeed: false` builds a simpler player -> mixer chain with no
    /// pitch variation — the fallback if the time effect is unsupported on
    /// this device. Pitch jitter is a nicety; silent dice are not.
    private func buildGraph(useVarispeed: Bool) -> Bool {
        // Canonical format taken from the mixer itself, so it matches the
        // hardware rather than the files.
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        guard mixerFormat.sampleRate > 0,
              let format = AVAudioFormat(
                  standardFormatWithSampleRate: mixerFormat.sampleRate,
                  channels: mixerFormat.channelCount
              )
        else {
            print("[DiceAudioEngine] no usable mixer format")
            return false
        }

        // Convert every sample once, up front — on the audio queue, which
        // owns `buffers`. A game's `preload` writes to it from that queue
        // while this runs on the main thread during scene assembly, and
        // the two used to be able to interleave.
        var survived = false
        audioQueue.sync {
            var converted: [String: [AVAudioPCMBuffer]] = [:]
            for (name, pool) in buffers {
                converted[name] = pool.compactMap { convert($0, to: format) }
            }
            survived = converted.values.contains(where: { !$0.isEmpty })
            if survived {
                buffers = converted
                graphFormat = format
            }
        }
        guard survived else {
            print("[DiceAudioEngine] no samples survived format conversion")
            return false
        }

        for _ in 0..<voiceCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            if useVarispeed {
                let speed = AVAudioUnitVarispeed()
                engine.attach(speed)
                engine.connect(player, to: speed, format: format)
                engine.connect(speed, to: engine.mainMixerNode, format: format)
                voices.append((player, speed))
            } else {
                engine.connect(player, to: engine.mainMixerNode, format: format)
                voices.append((player, nil))
            }
        }
        return !voices.isEmpty
    }

    private func teardownGraph() {
        for v in voices {
            engine.detach(v.player)
            if let s = v.speed { engine.detach(s) }
        }
        voices.removeAll()
    }

    /// Starts the audio graph. Safe to call repeatedly and safe to fail —
    /// every failure path leaves the game playable, just quieter.
    ///
    /// Tries the varispeed graph first, and if the engine refuses to start,
    /// rebuilds without the time effect and tries again. Connection errors
    /// surface only at start() time, so attempt-then-retry is the only way
    /// to detect this: engine.connect itself raises rather than returning
    /// an error.
    func start() {
        guard !isRunning else { return }
        _ = SoundEngine.shared   // ensures AVAudioSession is configured first

        // Unconditionally, and on the audio queue. `loadSet` returns
        // early for a set that is already in, so this costs nothing on a
        // restart — and it must not be skipped just because something
        // else is loaded: a game that preloads its own sets in onAppear
        // gets here with `buffers` non-empty, and an `isEmpty` check
        // would have left the dice themselves silent in exactly those
        // two games.
        audioQueue.sync {
            for tier in ImpactTier.allCases {
                loadSet("sfx_impact_" + tier.rawValue)
            }
        }

        for useVarispeed in [true, false] {
            if voices.isEmpty {
                guard buildGraph(useVarispeed: useVarispeed) else { return }
            }
            do {
                engine.prepare()
                try engine.start()
                for v in voices { v.player.play() }
                isRunning = true
                print("[DiceAudioEngine] started (pitchJitter: \(useVarispeed)), variants: \(loadedCounts)")
                return
            } catch {
                print("[DiceAudioEngine] start failed with varispeed=\(useVarispeed): \(error)")
                engine.stop()
                teardownGraph()
            }
        }
        print("[DiceAudioEngine] could not start audio; game continues silent")
    }

    // MARK: Playback

    /// Plays one impact.
    ///
    /// - Parameters:
    ///   - tier: which sample set to draw from.
    ///   - gain: 0...1 continuous loudness for this specific hit. Tier
    ///     selects timbre; this scales level within it. Driving volume
    ///     continuously is what stops a die bouncing down through the
    ///     tier thresholds from audibly "stepping" between layers.
    ///   - pan: -1 (left) ... 1 (right), from the die's screen position.
    func play(tier: ImpactTier, gain: Float, pan: Float) {
        play(set: "sfx_impact_" + tier.rawValue, gain: gain, pan: pan)
    }

    /// Plays one sample from a named set.
    ///
    /// - Parameters:
    ///   - set: the resource base name — `sfx_bb_bat`, `sfx_bot_cannon`.
    ///   - gain: 0...1, scaled by the player's effects volume.
    ///   - pan: -1 (left) ... 1 (right).
    ///   - jitter: whether to vary the pitch. On for the dice, where a
    ///     repeated variant would be caught immediately; **off** for a
    ///     sound a player hears a handful of times a match, where
    ///     varispeed would only make it sound wrong.
    ///   - delay: seconds to wait before it sounds. This is what a fly
    ///     out is made of: the bat, then the glove a beat later. Last in
    ///     the list because it reads as the timing after the sound: what
    ///     plays, then when.
    func play(set name: String, gain: Float = 1, pan: Float = 0,
              jitter: Bool = true, delay: TimeInterval = 0) {
        // Captured before hopping queues: these are read from SoundEngine,
        // whose @Published properties belong to the main thread.
        let enabled = SoundEngine.shared.sfxEnabled
        let masterVolume = Float(SoundEngine.shared.sfxVolume)
        guard enabled else { return }

        let fire: () -> Void = { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.loadSet(name)
            guard let pool = self.buffers[name], !pool.isEmpty else { return }

            let buffer = pool[self.nextFromBag(name, count: pool.count)]
            let voice = self.voices[self.nextVoice]
            self.nextVoice = (self.nextVoice + 1) % self.voices.count

            // nil when running the fallback graph without the time effect.
            voice.speed?.rate = jitter ? Float.random(in: self.pitchJitter) : 1.0
            voice.player.pan = max(-1, min(1, pan))
            voice.player.volume = max(0, min(1, gain)) * masterVolume

            // .interrupts: this voice is being reused round-robin, so any
            // older sound still on it should be cut rather than queued —
            // queueing would introduce growing latency under load.
            voice.player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        }

        // A delayed sound is scheduled on the same queue rather than with
        // an AVAudioTime: the gaps here are tenths of a second between
        // separate events, not sample-accurate layering, and asyncAfter
        // keeps every mutation of the bags and the voice cursor on the one
        // queue that owns them.
        if delay > 0 {
            audioQueue.asyncAfter(deadline: .now() + delay, execute: fire)
        } else {
            audioQueue.async(execute: fire)
        }
    }

    /// Next index from the set's shuffled bag, refilling when empty.
    private func nextFromBag(_ set: String, count: Int) -> Int {
        if bags[set]?.isEmpty ?? true {
            var fresh = Array(0..<count).shuffled()
            // Avoid the one case a bag can still repeat: the last item of
            // the old bag landing first in the new one.
            if count > 1, let last = lastPlayed[set], fresh.first == last {
                fresh.swapAt(0, count - 1)
            }
            bags[set] = fresh
        }
        // Non-forced: the refill above guarantees a non-empty bag, but a
        // crash in an audio path over a cosmetic sound would be a terrible
        // trade. Falling back to 0 degrades to "always variant 1", which
        // is inaudible-to-nobody rather than fatal.
        guard var bag = bags[set], !bag.isEmpty else { return 0 }
        let idx = bag.removeFirst()
        bags[set] = bag
        lastPlayed[set] = idx
        return idx
    }

    private var lastPlayed: [String: Int] = [:]

    /// Variant counts actually loaded, for diagnostics.
    var loadedCounts: [String: Int] {
        buffers.mapValues { $0.count }
    }
}
