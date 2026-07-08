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

    /// Fired on the main thread when the watch sends a control command
    /// ("start" or "stop"), so pressing either on one device brings the
    /// other along instead of leaving them out of sync.
    var onRemoteCommand: ((String) -> Void)?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func handle(_ payload: [String: Any]) {
        if let command = payload["command"] as? String {
            DispatchQueue.main.async { self.onRemoteCommand?(command) }
            return
        }
        guard let bpm = payload["bpm"] as? Double else { return }
        DispatchQueue.main.async {
            self.watchBPM = bpm
            self.lastUpdate = Date()
        }
    }

    /// Tells the watch to stop monitoring, mirroring a Stop press here.
    func sendStop() { sendControl("stop") }

    /// Tells the watch to start monitoring, mirroring a Listen press here.
    func sendStart() { sendControl("start") }

    private func sendControl(_ command: String) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload: [String: Any] = ["command": command]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? session.updateApplicationContext(payload)
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
