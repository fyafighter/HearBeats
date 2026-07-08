import SwiftUI

struct SettingsView: View {
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("mixWithOtherAudio") private var mixWithOtherAudio = true
    @AppStorage("heartbeatVolume") private var heartbeatVolume = 1.0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Keep Screen Awake While Listening", isOn: $keepScreenAwake)
                } footer: {
                    Text("Prevents the screen from locking while HearBeats is playing.")
                }

                Section {
                    Toggle("Mix with Other Audio", isOn: $mixWithOtherAudio)
                } footer: {
                    Text(mixWithOtherAudio
                        ? "HearBeats plays alongside other apps, like Spotify or Music."
                        : "HearBeats pauses other apps' audio while listening.")
                }

                Section {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: $heartbeatVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Heartbeat Volume")
                } footer: {
                    Text("Adjusts the heartbeat sound only, separate from your device's volume.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
