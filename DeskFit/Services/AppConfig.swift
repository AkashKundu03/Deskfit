import Foundation

/// Centralized app configuration. The backend base URL is resolved in ONE place
/// here — never hardcode it anywhere else. `APIClient` reads `backendBaseURL`.
///
/// How the URL is chosen:
///   • DEBUG + Simulator  → http://localhost:3000      (your Mac's local backend)
///   • DEBUG + real iPhone → http://<your Mac LAN IP>:3000  (see `macLANIP` below)
///   • RELEASE / TestFlight → production VPS            (unchanged — keeps Apple login working)
///
/// Switching environments is automatic by build configuration, so a Release/
/// TestFlight build can NEVER accidentally point at localhost.
enum AppConfig {

    // ─────────────────────────────────────────────────────────────────────────
    // 👇 THE ONLY LINE YOU EDIT for real-iPhone local testing.
    // Set this to your Mac's LAN IP (the iPhone must be on the SAME Wi-Fi).
    // Find it in Terminal with:   ipconfig getifaddr en0
    // (Wi-Fi is usually en0; if that's empty try en1.)
    static let macLANIP = "192.168.1.100"
    // ─────────────────────────────────────────────────────────────────────────

    /// Production backend on the VPS. Used for Release / TestFlight builds.
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
            #if targetEnvironment(simulator)
                // Simulator shares the Mac's network, so localhost reaches the local backend.
                return URL(string: "http://localhost:3000")!
            #else
                // Real device in Debug → your Mac on the LAN. iPhone "localhost" is the
                // iPhone itself, NOT your Mac — so a LAN IP is required here.
                return URL(string: "http://\(macLANIP):3000")!
            #endif
        #else
            // Release / TestFlight / App Store → production. Do not change casually.
            return productionBaseURL
        #endif
    }()
}
