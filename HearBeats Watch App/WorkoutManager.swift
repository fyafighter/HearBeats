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

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data not available on this device."
            return
        }
        let read: Set<HKObjectType> = [HKQuantityType.quantityType(forIdentifier: .heartRate)!]
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: share, read: read) { _, error in
            if let error {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Session control

    func startMonitoring() {
        errorMessage = nil
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore,
                                           configuration: configuration)
            builder = session?.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                          workoutConfiguration: configuration)
            session?.delegate = self
            builder?.delegate = self

            let start = Date()
            session?.startActivity(with: start)
            builder?.beginCollection(withStart: start) { _, error in
                if let error {
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                }
            }
            isMonitoring = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopMonitoring() {
        session?.end()
        isMonitoring = false
    }

    // MARK: - Sending to phone

    private func send(bpm: Double) {
        let payload: [String: Any] = ["bpm": bpm,
                                      "ts": Date().timeIntervalSince1970]
        let wcSession = WCSession.default
        if wcSession.isReachable {
            wcSession.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? wcSession.updateApplicationContext(payload)
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        if toState == .ended {
            builder?.endCollection(withEnd: date) { [weak self] _, _ in
                // We only monitor — no need to save a workout to Health.
                self?.builder?.discardWorkout()
                DispatchQueue.main.async {
                    self?.session = nil
                    self?.builder = nil
                    self?.heartRate = nil
                }
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.isMonitoring = false
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
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
}
