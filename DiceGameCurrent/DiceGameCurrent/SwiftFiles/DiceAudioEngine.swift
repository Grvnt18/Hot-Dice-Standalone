import AVFoundation
import Foundation

/// Impact velocity tiers. Raw values match the sample filename convention
/// (`sfx_impact_<tier>_NN.wav`), so adding variants is a matter of dropping
/// files in — no code change.
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

    /// Preloaded buffers per tier, decoded once at startup.
    private var buffers: [ImpactTier: [AVAudioPCMBuffer]] = [:]

    /// Shuffled play order per tier, consumed then reshuffled — a "bag".
    /// True random would repeat the same variant back-to-back roughly
    /// 1-in-N of the time, which the ear catches immediately; a bag
    /// guarantees every variant plays once before any repeats.
    private var bags: [ImpactTier: [Int]] = [:]

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

    private func loadBuffers() {
        for tier in ImpactTier.allCases {
            var loaded: [AVAudioPCMBuffer] = []
            // Probe sequentially; stops at the first gap, so variant count
            // is discovered from what's actually bundled.
            for n in 1...99 {
                let name = String(format: "sfx_impact_%@_%02d", tier.rawValue, n)
                guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                      let file = try? AVAudioFile(forReading: url),
                      let buf = AVAudioPCMBuffer(
                          pcmFormat: file.processingFormat,
                          frameCapacity: AVAudioFrameCount(file.length)
                      ),
                      (try? file.read(into: buf)) != nil
                else { break }
                loaded.append(buf)
            }
            buffers[tier] = loaded
            bags[tier] = []
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

        // Convert every sample once, up front.
        var converted: [ImpactTier: [AVAudioPCMBuffer]] = [:]
        for (tier, pool) in buffers {
            converted[tier] = pool.compactMap { convert($0, to: format) }
        }
        guard converted.values.contains(where: { !$0.isEmpty }) else {
            print("[DiceAudioEngine] no samples survived format conversion")
            return false
        }
        buffers = converted
        graphFormat = format

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

        if buffers.isEmpty { loadBuffers() }

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
        // Captured before hopping queues: these are read from SoundEngine,
        // whose @Published properties belong to the main thread.
        let enabled = SoundEngine.shared.sfxEnabled
        let masterVolume = Float(SoundEngine.shared.sfxVolume)
        guard enabled else { return }

        audioQueue.async { [weak self] in
            guard let self = self, self.isRunning,
                  let pool = self.buffers[tier], !pool.isEmpty
            else { return }

            let buffer = pool[self.nextFromBag(tier, count: pool.count)]
            let voice = self.voices[self.nextVoice]
            self.nextVoice = (self.nextVoice + 1) % self.voices.count

            // nil when running the fallback graph without the time effect.
            voice.speed?.rate = Float.random(in: self.pitchJitter)
            voice.player.pan = max(-1, min(1, pan))
            voice.player.volume = max(0, min(1, gain)) * masterVolume

            // .interrupts: this voice is being reused round-robin, so any
            // older sound still on it should be cut rather than queued —
            // queueing would introduce growing latency under load.
            voice.player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        }
    }

    /// Next index from the tier's shuffled bag, refilling when empty.
    private func nextFromBag(_ tier: ImpactTier, count: Int) -> Int {
        if bags[tier]?.isEmpty ?? true {
            var fresh = Array(0..<count).shuffled()
            // Avoid the one case a bag can still repeat: the last item of
            // the old bag landing first in the new one.
            if count > 1, let last = lastPlayed[tier], fresh.first == last {
                fresh.swapAt(0, count - 1)
            }
            bags[tier] = fresh
        }
        // Non-forced: the refill above guarantees a non-empty bag, but a
        // crash in an audio path over a cosmetic sound would be a terrible
        // trade. Falling back to 0 degrades to "always variant 1", which
        // is inaudible-to-nobody rather than fatal.
        guard var bag = bags[tier], !bag.isEmpty else { return 0 }
        let idx = bag.removeFirst()
        bags[tier] = bag
        lastPlayed[tier] = idx
        return idx
    }

    private var lastPlayed: [ImpactTier: Int] = [:]

    /// Variant counts actually loaded, for diagnostics.
    var loadedCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: ImpactTier.allCases.map {
            ($0.rawValue, buffers[$0]?.count ?? 0)
        })
    }
}
