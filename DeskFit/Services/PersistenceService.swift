import Foundation

enum PersistenceKey: String {
    case userProfile
    case gutAnswers
    case healthReport
    case onboardingComplete
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
        for key in [PersistenceKey.userProfile, .gutAnswers, .healthReport, .onboardingComplete] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
