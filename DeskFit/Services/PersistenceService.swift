import Foundation

enum PersistenceKey: String {
    case userProfile
    case gutAnswers
    case healthReport
    case onboardingComplete
    /// Set when the user explicitly chose "Continue without account".
    case guestMode
    /// Written once per install. UserDefaults is wiped on uninstall but the
    /// Keychain is NOT — its absence means a fresh install / reinstall, which is
    /// our cue to purge any stale Keychain session. Never cleared by user state.
    case installMarker
    // Real-user plan caches (NEVER used in demo mode — demo stays in-memory only,
    // keeping demo data fully separate from real user data).
    case weeklyPlanCache
    case mealPlanCache
    case standaloneCache
    case weeklyMealCache
}

struct PersistenceService {
    private let defaults = UserDefaults.standard

    func save<T: Encodable>(_ value: T, for key: PersistenceKey) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key.rawValue)
        }
    }

    func load<T: Decodable>(_ type: T.Type, for key: PersistenceKey) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func setFlag(_ value: Bool, for key: PersistenceKey) {
        defaults.set(value, forKey: key.rawValue)
    }

    func flag(for key: PersistenceKey) -> Bool {
        defaults.bool(forKey: key.rawValue)
    }

    func clearAll() {
        for key in [PersistenceKey.userProfile, .gutAnswers, .healthReport, .onboardingComplete,
                    .weeklyPlanCache, .mealPlanCache] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    /// Clears the generated report + onboarding flag while KEEPING the user's
    /// profile and gut answers. Used by "Retake assessment" so the questionnaire
    /// re-appears pre-filled without logging the user out.
    func clearReportAndOnboarding() {
        defaults.removeObject(forKey: PersistenceKey.healthReport.rawValue)
        defaults.set(false, forKey: PersistenceKey.onboardingComplete.rawValue)
    }

    /// Clears only the cached plans.
    func clearPlanCaches() {
        for key in [PersistenceKey.weeklyPlanCache, .mealPlanCache, .standaloneCache, .weeklyMealCache] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    /// Clears ALL on-device user state (real-user + guest), preserving only the
    /// install marker. Used on logout and on fresh-install/reinstall purge so a
    /// logged-out or freshly-installed app never resumes stale local data.
    func clearAllUserState() {
        for key in [PersistenceKey.userProfile, .gutAnswers, .healthReport,
                    .onboardingComplete, .guestMode, .weeklyPlanCache, .mealPlanCache, .standaloneCache, .weeklyMealCache] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
