import SwiftUI

struct WatchContentView: View {
    @StateObject private var workout = WorkoutManager()

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: workout.isMonitoring)

            Text(workout.heartRate.map { "\(Int($0))" } ?? "--")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text("BPM")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(workout.isMonitoring ? "Stop" : "Start") {
                workout.isMonitoring ? workout.stopMonitoring()
                                     : workout.startMonitoring()
            }
            .tint(workout.isMonitoring ? .gray : .red)

            if let error = workout.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else {
                Label(workout.isPhoneReachable ? "iPhone connected" : "iPhone not reachable",
                      systemImage: "iphone")
                    .font(.caption2)
                    .foregroundStyle(workout.isPhoneReachable ? .green : .secondary)
            }
        }
        .onAppear { workout.requestAuthorization() }
    }
}

#Preview {
    WatchContentView()
}
