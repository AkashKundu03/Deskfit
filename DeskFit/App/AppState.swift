import SwiftUI

@Observable
final class AppState {
    var profile: UserProfile
    var gutAnswers: GutAnswers
    var report: HealthReport?
    var onboardingComplete: Bool

    /// True when a JWT is present in the Keychain.
    private(set) var isAuthenticated: Bool = KeychainTokenStore.shared.isAuthenticated
    /// True when the user explicitly chose "Continue without account". Their data
    /// stays on-device only; premium generation is gated behind sign-in.
    private(set) var isGuest: Bool = false
    /// While true, the router shows the splash; we're resolving backend state.
    private(set) var isBootstrapping = true
    /// While true, the router shows the questionnaire directly (used by "Retake
    /// assessment" so the signed-in user stays logged in and goes straight to the
    /// questions — no intro / account-choice / logout).
    var isRetakingAssessment = false
    /// Drives the login gate: set true on logout so the router shows the sign-in
    /// screen without discarding the on-device report/profile.
    var requiresAuth: Bool = false
    /// Set when a best-effort backend sync fails; surfaced gently in the UI.
    var syncError: String?
    /// Timestamp of the last successful backend sync (for the Account & Sync card).
    var lastSyncedAt: Date?

    /// Backend snapshot fetched during an Apple sign-in, held so a conflict
    /// resolution ("Use Apple account profile") can hydrate from it.
    private var pendingBackendMe: MeResponse?

    private let persistence = PersistenceService()

    /// Outcome of an Apple sign-in, used by the UI to route / show conflict UI.
    enum AppleSignInOutcome: Equatable {
        case loadedBackend          // backend had an assessment → hydrated, go to app
        case noBackendNeedsAssessment // brand-new account, no local data → questionnaire
        case offerSaveLocal         // backend empty, local assessment exists → offer save
        case conflict               // both backend and local have an assessment
        case error(String)
    }

    init() {
        let p = PersistenceService()

        // ── Fresh-install / reinstall detection ──────────────────────────────
        // iOS wipes UserDefaults on uninstall but KEEPS the Keychain. Without a
        // marker, a deleted app would silently resume the old Keychain session and
        // jump straight to Today. If the marker is missing, treat this as a fresh
        // install: purge the stale Keychain token and any local user state so the
        // app starts from the intro. Backend/Apple-account data is untouched.
        if !p.flag(for: .installMarker) {
            KeychainTokenStore.shared.clearToken()
            p.clearAllUserState()
            p.setFlag(true, for: .installMarker)
        }

        self.profile = p.load(UserProfile.self, for: .userProfile) ?? UserProfile()
        self.gutAnswers = p.load(GutAnswers.self, for: .gutAnswers) ?? GutAnswers()
        self.report = p.load(HealthReport.self, for: .healthReport)
        self.onboardingComplete = p.flag(for: .onboardingComplete)
        self.isGuest = p.flag(for: .guestMode)
        // `isAuthenticated`'s inline default read the Keychain BEFORE this body ran,
        // so re-read after a possible fresh-install purge above.
        self.isAuthenticated = KeychainTokenStore.shared.isAuthenticated
    }

    func refreshAuthState() {
        isAuthenticated = KeychainTokenStore.shared.isAuthenticated
    }

    /// True once the user has an assessment on this device.
    var hasLocalAssessment: Bool {
        onboardingComplete && report != nil
    }

    /// Whether the main app (Today/tabs) may be shown. A completed assessment is
    /// not enough — the user must be either a signed-in Apple user OR an explicit
    /// guest. This prevents a logged-out user (or stale cache) from landing on
    /// Today without going through intro / account choice.
    var canShowMainApp: Bool {
        (isAuthenticated || isGuest) && onboardingComplete && report != nil
    }

    // MARK: - Launch bootstrap

    /// Resolve the right launch destination. If a token exists, pull the backend
    /// account so a returning Apple user on a fresh device skips the questionnaire.
    @MainActor
    func bootstrap() async {
        refreshAuthState()
        // Show the brand splash for a beat regardless of how fast the fetch is.
        async let minSplash: Void = Task.sleep(nanoseconds: 1_300_000_000)
        if isAuthenticated {
            do {
                let me = try await MeService().fetchMe()
                if me.hasAssessment {
                    hydrate(from: me)
                }
            } catch {
                // Offline / transient: fall back to whatever is cached on-device.
            }
        }
        try? await minSplash
        isBootstrapping = false
    }

    // MARK: - Account mode

    /// User tapped "Continue without account". Data stays local-only.
    func continueAsGuest() {
        isGuest = true
        persistence.setFlag(true, for: .guestMode)
    }

    /// Hydrate local models + report from a backend snapshot and mark onboarding
    /// complete. Backend data wins — used on launch and "Use Apple account profile".
    @MainActor
    func hydrate(from me: MeResponse) {
        if let p = me.profile { profile = p.toUserProfile() }
        if let g = me.gutAnswers { gutAnswers = g.toGutAnswers() }
        if let r = me.report?.toHealthReport() {
            report = r
            onboardingComplete = true
        }
        isGuest = false
        persistence.setFlag(false, for: .guestMode)
        persistAll()
    }

    // MARK: - Apple sign-in handling (incl. guest upgrade & conflict)

    /// Called after a successful Apple sign-in. Decides whether backend data wins,
    /// whether to offer saving the local assessment, or whether there's a conflict.
    @MainActor
    func handleAppleSignIn() async -> AppleSignInOutcome {
        refreshAuthState()
        isGuest = false
        persistence.setFlag(false, for: .guestMode)
        try? await EventSyncService().track("social_login_success")

        let localExists = hasLocalAssessment
        do {
            let me = try await MeService().fetchMe()
            pendingBackendMe = me
            switch (me.hasAssessment, localExists) {
            case (true, true):
                return .conflict                      // let the user choose
            case (true, false):
                hydrate(from: me)
                return .loadedBackend
            case (false, true):
                return .offerSaveLocal
            case (false, false):
                return .noBackendNeedsAssessment
            }
        } catch {
            // Couldn't reach backend. Never overwrite remote data on uncertainty.
            if localExists { return .offerSaveLocal }
            return .noBackendNeedsAssessment
        }
    }

    /// Conflict resolution / explicit choice: keep the backend's profile.
    @MainActor
    func useBackendProfile() {
        if let me = pendingBackendMe { hydrate(from: me) }
        pendingBackendMe = nil
    }

    /// Conflict resolution / "save this assessment": push local data to the
    /// account. Additive PUT — never deletes backend rows. Best-effort.
    @MainActor
    func uploadLocalAssessment() async {
        pendingBackendMe = nil
        guard isAuthenticated else { return }
        // Ensure a report exists so the account is fully populated.
        if report == nil { generateReport() }
        syncError = nil
        do {
            try await MeService().uploadAssessment(profile: profile, gut: gutAnswers, report: report)
            lastSyncedAt = Date()
        } catch {
            syncError = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't sync right now. Your data is saved on this device."
        }
    }

    /// Logs out: clears the JWT and ALL on-device real-user data (profile, gut
    /// answers, report, plans), then routes to the login screen. Backend data is
    /// never deleted — signing back in reloads everything from the account.
    func signOut() {
        AuthService().logout()
        clearLocalUserState()
        refreshAuthState()
        requiresAuth = true
    }

    /// Delete the account: backend wipes all data + revokes Apple credentials.
    /// On success, fully clear the device and route back to the intro.
    @MainActor
    func deleteAccount(reason: String?) async -> Bool {
        let ok = await AccountService().deleteNow(reason: reason)
        if ok {
            AuthService().logout()       // discard the (now-useless) token
            clearLocalUserState()
            refreshAuthState()
            requiresAuth = false
        }
        return ok
    }

    /// Schedule deletion in 7 days. Keeps the session so the user can recover.
    func scheduleAccountDeletion(reason: String?) async -> Bool {
        await AccountService().schedule(reason: reason)
    }

    /// Resets in-memory + persisted user state so a logged-out app shows no real
    /// data. Does NOT touch backend or the install marker.
    private func clearLocalUserState() {
        profile = UserProfile()
        gutAnswers = GutAnswers()
        report = nil
        onboardingComplete = false
        isGuest = false
        persistence.clearAllUserState()
    }

    /// Best-effort push of local data to the backend. Never blocks report
    /// generation. On failure it records a friendly message in `syncError`.
    @MainActor
    func syncAll() async {
        guard isAuthenticated else { return }
        syncError = nil
        do {
            try await ProfileSyncService().sync(profile)
            try await GutAnswersSyncService().sync(gutAnswers)
            if let report {
                try await ReportSyncService().sync(report)
                try await EventSyncService().track("assessment_completed")
            }
            lastSyncedAt = Date()
        } catch {
            syncError = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't sync right now. Your report is saved on this device."
        }
    }

    /// Called right after a successful social sign-in (before the report exists).
    /// Refreshes auth state and records the event. The actual data push happens
    /// later via syncAll() once the report is generated. Best-effort.
    @MainActor
    func registerSocialLogin() async {
        refreshAuthState()
        try? await EventSyncService().track("social_login_success")
    }

    func generateReport() {
        let bmi   = HealthCalculator.bmi(weightKg: profile.weightKg, heightCm: profile.heightCm)
        let cat   = HealthCalculator.category(for: bmi)
        let bmr   = HealthCalculator.bmr(weightKg: profile.weightKg, heightCm: profile.heightCm, age: profile.age, gender: profile.gender)
        let tdee  = HealthCalculator.tdee(bmr: bmr, activity: profile.activity)
        let range = HealthCalculator.healthyWeightRange(heightCm: profile.heightCm)
        let cal   = HealthCalculator.calorieTargetRange(tdee: tdee, goal: profile.goal)
        let gut   = GutHealthScorer.score(answers: gutAnswers)
        let age   = GutHealthScorer.gutAge(chronologicalAge: profile.age, score: gut)
        let acts  = RiskEngine.priorityActions(profile: profile, gut: gutAnswers, gutScore: gut)

        self.report = HealthReport(
            bmi: bmi,
            bmiCategory: cat,
            bmr: bmr,
            tdee: tdee,
            healthyWeightLowKg: range.low,
            healthyWeightHighKg: range.high,
            calorieTargetLow: cal.low,
            calorieTargetHigh: cal.high,
            gutScore: gut,
            gutAge: age,
            priorityActions: acts,
            generatedAt: Date()
        )
        self.onboardingComplete = true
        persistAll()
    }

    /// "Retake assessment" — keeps the user signed in (or in guest mode) and sends
    /// them straight to the questionnaire, pre-filled with their current answers.
    /// Clears only the report + onboarding flag so the questions re-appear; the
    /// auth token, guest status, profile, and gut answers are preserved. On finish,
    /// the report is regenerated and (if signed in) re-synced — NOT a logout.
    func retakeAssessment() {
        report = nil
        onboardingComplete = false
        isRetakingAssessment = true
        persistence.clearReportAndOnboarding()
    }

    private func persistAll() {
        persistence.save(profile, for: .userProfile)
        persistence.save(gutAnswers, for: .gutAnswers)
        if let report { persistence.save(report, for: .healthReport) }
        persistence.setFlag(onboardingComplete, for: .onboardingComplete)
    }
}
