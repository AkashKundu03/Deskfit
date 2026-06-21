import Foundation

enum PersistenceKey: String {
    case userProfile
    case gutAnswers
    case healthReport
    case onboardingComplete
    /// Set when the user explicitly chose "Continue without account".
    case guestMode
    // Real-user plan caches (NEVER used in demo mode — demo stays in-memory only,
    // keeping demo data fully separate from real user data).
    case weeklyPlanCache
    case mealPlanCache
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

    /// Clears only the cached plans (used on logout — keeps profile/report intact).
    func clearPlanCaches() {
        for key in [PersistenceKey.weeklyPlanCache, .mealPlanCache] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
