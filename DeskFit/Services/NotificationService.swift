import Foundation
import UserNotifications

/// The reminders DeskFit can schedule. Raw value doubles as the stable
/// notification identifier so re-scheduling replaces the previous request.
enum ReminderKind: String, CaseIterable, Identifiable, Codable {
    case workout
    case breakfast
    case lunch
    case dinner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workout: return "Workout reminder"
        case .breakfast: return "Breakfast reminder"
        case .lunch: return "Lunch reminder"
        case .dinner: return "Dinner reminder"
        }
    }

    var symbol: String {
        switch self {
        case .workout: return "figure.run"
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        }
    }

    /// Deep-link target tab when the notification is tapped.
    var deepLinkTab: AppTab {
        .today
    }

    var notificationBody: String {
        switch self {
        case .workout: return "Time to move — your session is waiting in DeskFit."
        case .breakfast: return "Breakfast time — hit your morning protein target."
        case .lunch: return "Lunch reminder — keep your day on track."
        case .dinner: return "Dinner reminder — finish strong and close your targets."
        }
    }

    var defaultHour: Int {
        switch self {
        case .workout: return 18
        case .breakfast: return 8
        case .lunch: return 13
        case .dinner: return 20
        }
    }
}

/// One reminder's on/off state and time-of-day.
struct ReminderSetting: Codable, Equatable {
    var enabled: Bool
    var hour: Int
    var minute: Int
}

/// Native local-notification scheduler (UNUserNotificationCenter). Stores each
/// reminder's settings + identifier on-device. Firebase is intentionally NOT used.
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// Current per-kind settings (persisted in UserDefaults).
    private(set) var settings: [ReminderKind: ReminderSetting] = [:]
    /// Last known system authorization status.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let defaultsKey = "reminderSettings.v1"
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        load()
    }

    /// Wire up tap handling. Call once at app launch.
    func configure() {
        center.delegate = self
        refreshAuthorizationStatus()
    }

    func setting(for kind: ReminderKind) -> ReminderSetting {
        settings[kind] ?? ReminderSetting(enabled: false, hour: kind.defaultHour, minute: 0)
    }

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { [weak self] s in
            Task { @MainActor in self?.authorizationStatus = s.authorizationStatus }
        }
    }

    /// Read the current authorization status WITHOUT prompting the user.
    @MainActor
    func refreshStatus() async {
        let s = await center.notificationSettings()
        authorizationStatus = s.authorizationStatus
    }

    /// Request permission at the RIGHT time (on first reminder enable), never on
    /// cold launch. Returns whether permission is granted.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let current = await center.notificationSettings()
        await MainActor.run { self.authorizationStatus = current.authorizationStatus }
        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await MainActor.run { self.refreshAuthorizationStatus() }
            return granted
        }
    }

    /// Enable/update a reminder. Requests permission first if needed, schedules a
    /// repeating daily notification, and replaces any existing one for this kind.
    @discardableResult
    func enable(_ kind: ReminderKind, hour: Int, minute: Int) async -> Bool {
        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return false }

        let setting = ReminderSetting(enabled: true, hour: hour, minute: minute)
        await MainActor.run { self.settings[kind] = setting; self.save() }

        schedule(kind, hour: hour, minute: minute)
        return true
    }

    /// Turn a reminder off and cancel its pending notification.
    func disable(_ kind: ReminderKind) {
        var setting = self.setting(for: kind)
        setting.enabled = false
        settings[kind] = setting
        save()
        center.removePendingNotificationRequests(withIdentifiers: [kind.rawValue])
    }

    /// Move a reminder to a new time without changing its enabled state.
    func reschedule(_ kind: ReminderKind, hour: Int, minute: Int) {
        var setting = self.setting(for: kind)
        setting.hour = hour
        setting.minute = minute
        settings[kind] = setting
        save()
        if setting.enabled {
            schedule(kind, hour: hour, minute: minute)
        }
    }

    /// Cancel a one-off / today's reminder for a kind (e.g. when the workout or
    /// meal is completed or skipped). The recurring daily reminder stays unless
    /// the user disabled it in settings.
    func cancelToday(_ kind: ReminderKind) {
        // The repeating reminder uses the kind's id; removing it stops further
        // fires until re-enabled. Used when an item is completed/skipped so the
        // user isn't nagged for something already handled.
        center.removePendingNotificationRequests(withIdentifiers: [kind.rawValue])
    }

    private let recoveryNudgeId = "recovery_nudge"

    /// A discreet, opt-in recovery nudge. Generic copy only — never exposes any
    /// health detail on the lock screen. Fires once, a few hours out.
    func scheduleRecoveryNudge() async {
        guard await requestAuthorizationIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "DeskFit"
        content.body = "Your recovery signals differ from usual. Open DeskFit to review today’s plan."
        content.sound = .default
        // No userInfo health details; deep-links to Today.
        content.userInfo = ["reminderKind": ReminderKind.workout.rawValue]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3 * 60 * 60, repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [recoveryNudgeId])
        try? await center.add(UNNotificationRequest(identifier: recoveryNudgeId, content: content, trigger: trigger))
    }

    func cancelRecoveryNudge() {
        center.removePendingNotificationRequests(withIdentifiers: [recoveryNudgeId])
    }

    // MARK: - Scheduling

    private func schedule(_ kind: ReminderKind, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "DeskFit"
        content.body = kind.notificationBody
        content.sound = .default
        content.userInfo = ["reminderKind": kind.rawValue]

        var date = DateComponents()
        date.hour = hour
        date.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: kind.rawValue, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [kind.rawValue])
        center.add(request)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: ReminderSetting].self, from: data)
        else { return }
        var mapped: [ReminderKind: ReminderSetting] = [:]
        for (k, v) in decoded {
            if let kind = ReminderKind(rawValue: k) { mapped[kind] = v }
        }
        settings = mapped
    }

    private func save() {
        let encodable = Dictionary(uniqueKeysWithValues: settings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while the app is foregrounded.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Route taps to the relevant screen.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let raw = response.notification.request.content.userInfo["reminderKind"] as? String
        if let raw, let kind = ReminderKind(rawValue: raw) {
            await MainActor.run { AppNavigation.shared.selectedTab = kind.deepLinkTab }
        }
    }
}
