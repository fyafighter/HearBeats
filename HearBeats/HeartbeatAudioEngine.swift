import AVFoundation
import Combine

/// Synthesizes a stethoscope-style "lub-dub" and plays it at a given BPM.
/// Each scheduled buffer is exactly one beat long (lub + dub + silence),
/// so tempo changes take effect on the next beat with no gaps or clicks.
/// Each thump is a resonant body excited by noise (not a tone), with the
/// resonance's pitch dropping sharply on attack for punch, then the whole
/// buffer is muffled, warmed, and given a touch of room entirely in
/// software — AVAudioUnitEQ/Reverb are unreliable in the iOS Simulator
/// (fails to initialize with error -10868), so the "chestpiece" coloring is
/// done as plain math on the buffer instead of engine nodes.
final class HeartbeatAudioEngine: ObservableObject {

    @Published private(set) var isPlaying = false

    /// Target heart rate. Clamped to a safe audible range.
    var bpm: Double {
        get { queue.sync { _bpm } }
        set { queue.sync { _bpm = min(max(newValue, 25), 220) } }
    }

    /// Fired on the main thread at the start of each beat (for UI pulse).
    var onBeat: (() -> Void)?

    private var _bpm: Double = 60
    private let queue = DispatchQueue(label: "HeartbeatAudioEngine.state")

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var sampleRate: Double = 44_100
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                            channels: 1)!

    // MARK: - Control

    func start() {
        guard !isPlaying else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            if !engine.attachedNodes.contains(player) {
                let hwSampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
                if hwSampleRate > 0 { sampleRate = hwSampleRate }
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }
            engine.prepare()
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
            return
        }

        isPlaying = true
        player.play()
        // Keep one buffer in flight ahead of the one playing.
        scheduleNextBeat(notify: true)
        scheduleNextBeat(notify: false)
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }

    // MARK: - Scheduling

    private func scheduleNextBeat(notify: Bool) {
        guard isPlaying else { return }
        let buffer = makeBeatBuffer(bpm: bpm)
        // .dataPlayedBack fires when this buffer finishes playing, i.e. exactly
        // on the next beat boundary — schedule the following beat then.
        player.scheduleBuffer(buffer, at: nil, options: [],
                              completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            DispatchQueue.main.async { self.onBeat?() }
            self.scheduleNextBeat(notify: false)
        }
        if notify { DispatchQueue.main.async { self.onBeat?() } }
    }

    // MARK: - Synthesis

    /// One full beat: S1 ("lub") at t = 0, S2 ("dub") after the systolic
    /// interval, then silence out to the full beat period. Timing and
    /// loudness are jittered slightly beat to beat — a perfectly identical
    /// loop is what makes synthesized audio read as synthetic.
    private func makeBeatBuffer(bpm: Double) -> AVAudioPCMBuffer {
        let period = 60.0 / bpm
        // Systole shortens as heart rate rises (~Bazett scaling).
        let systole = min(0.32 * (60.0 / bpm).squareRoot(), period * 0.45)
        func jitter(_ spread: Double) -> Double { Double.random(in: -spread...spread) }

        let frameCount = AVAudioFrameCount(period * sampleRate)
        let n = Int(frameCount)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]

        // Start from silence.
        for i in 0..<n { samples[i] = 0 }

        // S1 ("lub"): AV valve closure — low, longer, loudest, dullest.
        writeThump(into: samples, totalFrames: n,
                   startTime: max(0, jitter(0.004)),
                   startFrequency: 68, endFrequency: 32, pitchTau: 0.020, qFactor: 2.0,
                   decay: 0.060, duration: 0.19,
                   amplitude: 0.95 * (1 + jitter(0.05)))
        // S2 ("dub"): semilunar valve closure — higher, shorter, crisper.
        writeThump(into: samples, totalFrames: n,
                   startTime: max(0, systole + jitter(0.004)),
                   startFrequency: 96, endFrequency: 46, pitchTau: 0.013, qFactor: 3.0,
                   decay: 0.038, duration: 0.14,
                   amplitude: 0.60 * (1 + jitter(0.05)))

        // A faint, ever-present noise floor — real auscultation is never
        // dead silent between beats, and true digital silence is what reads
        // as "synthesized" to the ear.
        for i in 0..<n { samples[i] += Float(0.012 * Double.random(in: -1...1)) }

        applyChestCharacter(to: samples, count: n)

        // Gentle soft-clip so overlapping tails never crackle.
        for i in 0..<n { samples[i] = tanh(samples[i] * 1.15) }
        return buffer
    }

    /// A thump built by exciting a resonant body with noise, not by playing
    /// a tone — a real valve closure rings a resonant cavity, it doesn't
    /// emit a clean sine wave. The resonance's center frequency drops
    /// sharply on attack (the same punch a kick drum's pitch envelope
    /// gives), and its Q controls how "tuned" vs. dull the thump sounds.
    private func writeThump(into samples: UnsafeMutablePointer<Float>,
                            totalFrames: Int,
                            startTime: Double,
                            startFrequency: Double,
                            endFrequency: Double,
                            pitchTau: Double,
                            qFactor: Double,
                            decay: Double,
                            duration: Double,
                            amplitude: Double) {
        let startFrame = Int(startTime * sampleRate)
        guard startFrame >= 0, startFrame < totalFrames else { return }
        let thumpFrames = min(Int(duration * sampleRate), totalFrames - startFrame)
        guard thumpFrames > 0 else { return }

        var resonance = Biquad()
        for i in 0..<thumpFrames {
            let t = Double(i) / sampleRate
            let attack = 1.0 - exp(-t / 0.003)
            let envelope = attack * exp(-t / decay)

            // Pitch drops from startFrequency toward endFrequency for punch,
            // the way a struck resonant body's ring settles toward its
            // natural low frequency.
            let freq = endFrequency + (startFrequency - endFrequency) * exp(-t / pitchTau)
            resonance.tuneBandpass(sampleRate: sampleRate, frequency: freq, q: qFactor)

            let excited = resonance.process(Double.random(in: -1...1))
            // Bandpass filtering removes most of the noise's energy; scale
            // back up so amplitude still means what it says.
            samples[startFrame + i] += Float(amplitude * envelope * excited * 12.0)
        }
    }

    /// Muffles the buffer the way a diaphragm against skin does, adds a
    /// touch of warmth around 70 Hz, and layers in two short, quiet echoes
    /// to suggest chest-cavity space — an all-software stand-in for the
    /// AVAudioUnitEQ/Reverb chain this can't rely on in the Simulator.
    private func applyChestCharacter(to samples: UnsafeMutablePointer<Float>, count: Int) {
        let delayA = Int(0.021 * sampleRate)
        let delayB = Int(0.043 * sampleRate)
        if count > delayB {
            let dry = Array(UnsafeBufferPointer(start: samples, count: count))
            for i in stride(from: count - 1, through: delayA, by: -1) {
                var v = dry[i]
                v += 0.15 * dry[i - delayA]
                if i >= delayB { v += 0.08 * dry[i - delayB] }
                samples[i] = v
            }
        }

        var lowpass = Biquad.lowpass(sampleRate: sampleRate, cutoff: 240, q: 0.707)
        var warmth = Biquad.peaking(sampleRate: sampleRate, frequency: 55, q: 1.1, gainDB: 5)
        for i in 0..<count {
            samples[i] = Float(warmth.process(lowpass.process(Double(samples[i]))))
        }
    }
}

/// A minimal RBJ-cookbook biquad filter for shaping the synthesized buffer
/// without depending on AVAudioEngine effect nodes.
private struct Biquad {
    private var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func lowpass(sampleRate: Double, cutoff: Double, q: Double) -> Biquad {
        let w0 = 2.0 * .pi * cutoff / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cosw0 = cos(w0)
        let a0 = 1.0 + alpha
        var f = Biquad()
        f.b0 = ((1.0 - cosw0) / 2.0) / a0
        f.b1 = (1.0 - cosw0) / a0
        f.b2 = ((1.0 - cosw0) / 2.0) / a0
        f.a1 = (-2.0 * cosw0) / a0
        f.a2 = (1.0 - alpha) / a0
        return f
    }

    static func peaking(sampleRate: Double, frequency: Double, q: Double, gainDB: Double) -> Biquad {
        let a = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * .pi * frequency / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cosw0 = cos(w0)
        let a0 = 1.0 + alpha / a
        var f = Biquad()
        f.b0 = (1.0 + alpha * a) / a0
        f.b1 = (-2.0 * cosw0) / a0
        f.b2 = (1.0 - alpha * a) / a0
        f.a1 = (-2.0 * cosw0) / a0
        f.a2 = (1.0 - alpha / a) / a0
        return f
    }

    /// Recomputes coefficients in place (keeping delay state) so the same
    /// filter instance can be swept in frequency sample by sample.
    mutating func tuneBandpass(sampleRate: Double, frequency: Double, q: Double) {
        let w0 = 2.0 * .pi * frequency / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cosw0 = cos(w0)
        let a0 = 1.0 + alpha
        b0 = alpha / a0
        b1 = 0.0
        b2 = -alpha / a0
        a1 = (-2.0 * cosw0) / a0
        a2 = (1.0 - alpha) / a0
    }

    mutating func process(_ x0: Double) -> Double {
        let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x0
        y2 = y1; y1 = y0
        return y0
    }
}
