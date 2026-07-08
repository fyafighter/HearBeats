import Foundation
import HealthKit
import WatchConnectivity

/// Runs a HealthKit workout session to get live heart rate (updates every
/// few seconds) and streams each reading to the paired iPhone.
final class WorkoutManager: NSObject, ObservableObject {

    @Published var heartRate: Double?
    @Published var isMonitoring = false
    @Published var isPhoneReachable = false
    @Published var errorMessage: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Authorization

    /// Requests HealthKit access and starts monitoring immediately on
    /// success, so the workout session begins without the user pressing
    /// Start.
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data not available on this device."
            return
        }
        let read: Set<HKObjectType> = [HKQuantityType.quantityType(forIdentifier: .heartRate)!]
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: share, read: read) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error {
                    self?.errorMessage = error.localizedDescription
                } else if success {
                    self?.startMonitoring()
                }
            }
        }
    }

    // MARK: - Session control

    /// Starts locally and tells the phone to start too, mirroring
    /// `stopMonitoring()` — pressing Start on either device should bring
    /// the other one along instead of leaving them out of sync.
    func startMonitoring() {
        startMonitoringLocally()
        sendControl("start")
    }

    private func startMonitoringLocally() {
        guard !isMonitoring else { return }
        errorMessage = nil
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor

        do {
            let newSession = try HKWorkoutSession(healthStore: healthStore,
                                                  configuration: configuration)
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                            workoutConfiguration: configuration)
            newSession.delegate = self
            newBuilder.delegate = self
            session = newSession
            builder = newBuilder

            let start = Date()
            newSession.startActivity(with: start)
            newBuilder.beginCollection(withStart: start) { [weak self] _, error in
                if let error {
                    DispatchQueue.main.async { self?.errorMessage = error.localizedDescription }
                }
            }
            isMonitoring = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stops locally and tells the phone to stop too, so a single Stop
    /// press ends the session on both devices instead of leaving the phone
    /// playing (or the watch monitoring) with no way to tell why.
    func stopMonitoring() {
        stopMonitoringLocally()
        sendControl("stop")
    }

    private func stopMonitoringLocally() {
        guard isMonitoring else { return }
        isMonitoring = false
        heartRate = nil
        session?.end()
    }

    // MARK: - Sending to phone

    private func send(bpm: Double) {
        let payload: [String: Any] = ["bpm": bpm,
                                      "ts": Date().timeIntervalSince1970]
        sendToPhone(payload)
    }

    private func sendControl(_ command: String) {
        sendToPhone(["command": command])
    }

    private func sendToPhone(_ payload: [String: Any]) {
        let wcSession = WCSession.default
        guard wcSession.activationState == .activated else { return }
        if wcSession.isReachable {
            wcSession.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? wcSession.updateApplicationContext(payload)
        }
    }

    // MARK: - Receiving from phone

    private func handleIncoming(_ payload: [String: Any]) {
        guard let command = payload["command"] as? String else { return }
        DispatchQueue.main.async {
            switch command {
            case "stop": self.stopMonitoringLocally()
            case "start": self.startMonitoringLocally()
            default: break
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        // A Stop immediately followed by a Start (from either device, or a
        // rapid double-tap) can leave this callback firing for a session
        // that's no longer the current one — only tear down state if it
        // still belongs to the session that's actually ending.
        guard toState == .ended, workoutSession === session else { return }
        let endingBuilder = builder
        endingBuilder?.endCollection(withEnd: date) { _, _ in
            // We only monitor — no need to save a workout to Health.
            endingBuilder?.discardWorkout()
            DispatchQueue.main.async { [weak self] in
                guard let self, workoutSession === self.session else { return }
                self.session = nil
                self.builder = nil
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        DispatchQueue.main.async {
            guard workoutSession === self.session else { return }
            self.errorMessage = error.localizedDescription
            self.isMonitoring = false
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // Ignore stragglers from a builder that's since been replaced or
        // torn down — this is what previously let a stopped session's
        // in-flight reading revive playback on the phone right after Stop.
        guard workoutBuilder === builder else { return }
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        guard collectedTypes.contains(heartRateType),
              let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity() else { return }

        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        DispatchQueue.main.async { self.heartRate = bpm }
        send(bpm: bpm)
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

// MARK: - WCSessionDelegate

extension WorkoutManager: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { self.isPhoneReachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isPhoneReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncoming(applicationContext)
    }
}
