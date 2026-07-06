import AVFoundation
import Combine

/// Synthesizes a stethoscope-style "lub-dub" and plays it at a given BPM.
/// Each scheduled buffer is exactly one beat long (lub + dub + silence),
/// so tempo changes take effect on the next beat with no gaps or clicks.
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
    private let sampleRate: Double = 44_100
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                            channels: 1)!

    // MARK: - Control

    func start() {
        guard !isPlaying else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            if engine.attachedNodes.isEmpty || !engine.attachedNodes.contains(player) {
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
    /// interval, then silence out to the full beat period.
    private func makeBeatBuffer(bpm: Double) -> AVAudioPCMBuffer {
        let period = 60.0 / bpm
        // Systole shortens as heart rate rises (~Bazett scaling).
        let systole = min(0.32 * (60.0 / bpm).squareRoot(), period * 0.45)

        let frameCount = AVAudioFrameCount(period * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]

        // Start from silence.
        for i in 0..<Int(frameCount) { samples[i] = 0 }

        // S1: lower, longer, louder. S2: higher, shorter, softer.
        writeThump(into: samples, totalFrames: Int(frameCount),
                   startTime: 0.0, frequency: 52, decay: 0.045,
                   duration: 0.16, amplitude: 0.90)
        writeThump(into: samples, totalFrames: Int(frameCount),
                   startTime: systole, frequency: 68, decay: 0.030,
                   duration: 0.11, amplitude: 0.62)

        // Gentle soft-clip so overlapping tails never crackle.
        for i in 0..<Int(frameCount) { samples[i] = tanh(samples[i]) }
        return buffer
    }

    /// A damped low-frequency thump with a fast attack (no click) and a
    /// touch of second harmonic for body.
    private func writeThump(into samples: UnsafeMutablePointer<Float>,
                            totalFrames: Int,
                            startTime: Double,
                            frequency: Double,
                            decay: Double,
                            duration: Double,
                            amplitude: Double) {
        let startFrame = Int(startTime * sampleRate)
        let thumpFrames = min(Int(duration * sampleRate), totalFrames - startFrame)
        guard thumpFrames > 0 else { return }

        for n in 0..<thumpFrames {
            let t = Double(n) / sampleRate
            let attack = 1.0 - exp(-t / 0.004)
            let envelope = attack * exp(-t / decay)
            let fundamental = sin(2.0 * .pi * frequency * t)
            let harmonic = 0.35 * sin(2.0 * .pi * frequency * 2.0 * t)
            samples[startFrame + n] += Float(amplitude * envelope * (fundamental + harmonic))
        }
    }
}
