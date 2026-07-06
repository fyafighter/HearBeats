import SwiftUI

enum BeatSource: String, CaseIterable, Identifiable {
    case watch = "Watch"
    case demo = "Demo"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var audio = HeartbeatAudioEngine()
    @StateObject private var connectivity = PhoneConnectivity()

    @State private var source: BeatSource = .watch
    @State private var demoBPM: Double = 60
    @State private var heartScale: CGFloat = 1.0

    private var displayBPM: Double? {
        switch source {
        case .demo: return demoBPM
        case .watch: return connectivity.hasFreshReading ? connectivity.watchBPM : nil
        }
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 110))
                .foregroundStyle(.red.gradient)
                .scaleEffect(heartScale)

            VStack(spacing: 4) {
                Text(displayBPM.map { "\(Int($0))" } ?? "--")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("BPM")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Picker("Source", selection: $source) {
                ForEach(BeatSource.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)

            Group {
                if source == .demo {
                    VStack {
                        Slider(value: $demoBPM, in: 30...180, step: 1)
                        Text("Drag to set the demo heart rate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 40)
                } else {
                    Label(
                        connectivity.hasFreshReading
                            ? "Live from Apple Watch"
                            : connectivity.isWatchReachable
                                ? "Watch connected — start monitoring on the watch"
                                : "Waiting for Apple Watch…",
                        systemImage: connectivity.hasFreshReading
                            ? "applewatch.radiowaves.left.and.right"
                            : "applewatch"
                    )
                    .font(.callout)
                    .foregroundStyle(connectivity.hasFreshReading ? .green : .secondary)
                }
            }
            .frame(minHeight: 60)

            Button {
                if audio.isPlaying {
                    audio.stop()
                } else if let bpm = displayBPM {
                    audio.bpm = bpm
                    audio.start()
                }
            } label: {
                Label(audio.isPlaying ? "Stop" : "Listen",
                      systemImage: audio.isPlaying ? "stop.fill" : "stethoscope")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(audio.isPlaying ? .gray : .red)
            .disabled(!audio.isPlaying && displayBPM == nil)
            .padding(.horizontal, 40)

            Spacer()
        }
        .onAppear {
            audio.onBeat = { pulseHeart() }
        }
        .onChange(of: displayBPM) {
            if let bpm = displayBPM { audio.bpm = bpm }
        }
    }

    private func pulseHeart() {
        withAnimation(.easeOut(duration: 0.12)) { heartScale = 1.18 }
        withAnimation(.easeIn(duration: 0.30).delay(0.12)) { heartScale = 1.0 }
    }
}

#Preview {
    ContentView()
}
