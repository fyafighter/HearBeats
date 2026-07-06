import Foundation
import WatchConnectivity

/// Receives live heart rate messages from the watch app.
final class PhoneConnectivity: NSObject, ObservableObject, WCSessionDelegate {

    @Published var watchBPM: Double?
    @Published var lastUpdate: Date?
    @Published var isWatchReachable = false

    /// True if we have a reading from the last few seconds.
    var hasFreshReading: Bool {
        guard let lastUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < 10
    }

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func handle(_ payload: [String: Any]) {
        guard let bpm = payload["bpm"] as? Double else { return }
        DispatchQueue.main.async {
            self.watchBPM = bpm
            self.lastUpdate = Date()
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { self.isWatchReachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isWatchReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
