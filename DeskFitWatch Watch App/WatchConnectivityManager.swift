import Foundation
import WatchConnectivity

/// Watch side of WatchConnectivity. Receives the daily snapshot from the phone
/// and sends actions (meal/workout completions, check-ins) back. Used only for
/// live coordination — saved workout "truth" goes through HealthKit.
@Observable
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    private(set) var snapshot: WatchSnapshot?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send an action to the phone (queued via transferUserInfo if unreachable).
    func send(_ message: WatchActionMessage) {
        guard let data = try? JSONEncoder().encode(message),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(dict, replyHandler: nil, errorHandler: { _ in
                WCSession.default.transferUserInfo(dict)
            })
        } else {
            WCSession.default.transferUserInfo(dict)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        // Pull the latest snapshot the phone left in application context.
        applyContext(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyContext(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyContext(message)
    }

    private func applyContext(_ ctx: [String: Any]) {
        guard let raw = ctx["snapshot"],
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let snap = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        Task { @MainActor in self.snapshot = snap }
    }
}
