import Foundation

/// How plans are generated. Deterministic (rule-based) is the current and default
/// engine. The `ai` case is a placeholder for a future API-backed engine — there
/// is intentionally NO implementation behind it yet.
enum GenerationEngineMode {
    case deterministic
    case ai
}

/// Result of asking whether the user may generate a cloud-synced plan.
enum PlanAccess: Equatable {
    /// Authenticated + entitled: generation may proceed and persist to backend.
    case allowed
    /// Guest (no account): show the sign-in gate before generating.
    case needsSignIn
    /// Signed in but not subscribed (future real-IAP path).
    case needsSubscription
}

/// Central access / entitlement layer. Real App Store subscriptions will plug in
/// here later (StoreKit). For now `hasActiveSubscription` is a placeholder that is
/// `true` for internal/TestFlight/dev so our own testing is never blocked.
///
/// Premium-gated features (weekly workout plan + meal plan generation) ask
/// `planAccess(isAuthenticated:)`. Guests are always gated to sign-in first so
/// guest data never becomes cloud-synced; signed-in internal testers pass.
@Observable
final class EntitlementService {
    static let shared = EntitlementService()

    /// The generation engine in use. Keep `.deterministic` until an AI engine is
    /// actually implemented and reviewed.
    static let generationEngine: GenerationEngineMode = .deterministic

    /// Feature-flag override. Flip to gate premium even for signed-in testers when
    /// validating the subscription UX. Defaults to on for internal builds.
    var premiumOverrideEnabled: Bool = true

    /// Placeholder entitlement. Will be replaced by a StoreKit transaction check.
    /// True for internal/TestFlight/dev builds so testing is never blocked.
    var hasActiveSubscription: Bool {
        #if DEBUG
        return true
        #else
        // TestFlight/internal: keep true until real IAP ships. Production release
        // gating will replace this with a verified StoreKit entitlement.
        return premiumOverrideEnabled
        #endif
    }

    /// Copy shown on the (non-blocking) subscription placeholder.
    static let subscriptionPlaceholderCopy =
        "Subscription will be required for unlimited plans."

    private init() {}

    /// Decide whether a premium generation action may proceed.
    func planAccess(isAuthenticated: Bool) -> PlanAccess {
        guard isAuthenticated else { return .needsSignIn }
        return hasActiveSubscription ? .allowed : .needsSubscription
    }
}
