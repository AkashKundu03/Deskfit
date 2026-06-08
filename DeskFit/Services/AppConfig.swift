import Foundation

/// Centralized app configuration. Change the backend URL in ONE place here.
enum AppConfig {
#if targetEnvironment(simulator)
    // Simulator shares the Mac's network, so localhost reaches the local backend.
    static let backendBaseURL = URL(string: "http://localhost:3000")!
#else
    // Physical device uses the VPS-hosted backend.
    static let backendBaseURL = deviceBaseURL
#endif

    /// Backend on the VPS (used on a physical device).
    /// NOTE: plain HTTP for testing — switch to https://<domain> once TLS is set up.
    static let deviceBaseURL = URL(string: "http://45.195.159.233:3000")!
}
