import Foundation

/// Centralized app configuration. The backend base URL is resolved in ONE place
/// here — never hardcode it anywhere else. `APIClient` reads `backendBaseURL`.
///
/// How the URL is chosen (see `backendBaseURL` below):
///   • RELEASE / TestFlight / App Store → ALWAYS production VPS.
///   • DEBUG → controlled by `forceProductionAPIInDebug`:
///       - true  → production VPS on BOTH Simulator and real iPhone.
///       - false → Simulator uses localhost, real iPhone uses `macLANIP`.
///
/// A Release/TestFlight build can NEVER point at localhost or your Mac.
enum AppConfig {

    // ─────────────────────────────────────────────────────────────────────────
    // 👇 PRIMARY SWITCH for Debug builds.
    // true  → Debug builds (Simulator AND real iPhone) hit the PRODUCTION API.
    //         Use this to test on your iPhone from Xcode against the live server.
    // false → Debug builds hit your LOCAL backend (Simulator: localhost,
    //         real iPhone: `macLANIP`). Use this for local backend development.
    // (Release/TestFlight ignore this — they always use production.)
    static let forceProductionAPIInDebug = true
    // ─────────────────────────────────────────────────────────────────────────

    // Used only when forceProductionAPIInDebug == false AND running on a real
    // iPhone in Debug. Set to your Mac's LAN IP (iPhone must be on the SAME Wi-Fi).
    // Find it in Terminal with:   ipconfig getifaddr en0   (try en1 if en0 is empty).
    static let macLANIP = "192.168.1.100"

    /// Production backend on the VPS. Used for Release / TestFlight builds, and
    /// for Debug when `forceProductionAPIInDebug` is true.
    /// NOTE: plain HTTP for now — switch to https://<domain> once TLS is set up.
    static let productionBaseURL = URL(string: "http://45.195.159.233:3000")!

    // ─────────────────────────────────────────────────────────────────────────
    // DEMO MODE — for VC demos. When on, the coach UI is driven entirely by the
    // local deterministic engine using a fixed sample profile (no backend, no
    // network, no AI). Easy to disable: set `useDemoData = false`.
    // ─────────────────────────────────────────────────────────────────────────
    static var useDemoData = false

    /// The headline demo persona: busy IT worker, 75 kg → 65 kg in 4 months.
    static let demoProfile = UserProfile(
        name: "Arjun", age: 31, gender: .male,
        heightCm: 178, weightKg: 75, targetWeightKg: 65,
        activity: .sedentary, goal: .fatLoss, medicalFlags: [.none]
    )
    static let demoTimelineMonths: Int = 4
    /// Demo narrative: the user missed Friday's session (drives the adaptation card).
    static let demoMissedWeekday: String = "Fri"

    /// Resolved backend base URL for the current build configuration.
    static let backendBaseURL: URL = {
        #if DEBUG
            // Debug: honor the primary switch first.
            if forceProductionAPIInDebug {
                // Both Simulator and real iPhone hit production (current testing mode).
                return productionBaseURL
            }
            #if targetEnvironment(simulator)
                // Local dev on Simulator → localhost reaches your Mac's backend.
                return URL(string: "http://localhost:3000")!
            #else
                // Local dev on a real iPhone → your Mac on the LAN. iPhone "localhost"
                // is the iPhone itself, NOT your Mac — so a LAN IP is required here.
                return URL(string: "http://\(macLANIP):3000")!
            #endif
        #else
            // Release / TestFlight / App Store → production. Do not change casually.
            return productionBaseURL
        #endif
    }()
}
