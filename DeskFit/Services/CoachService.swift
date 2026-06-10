import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Talks to the backend deterministic coach engine, with a graceful local
// fallback (CoachEngine) so the premium UI is NEVER blank — even with no network
// or in demo mode. The UI does not depend on the production server for testing.
// ─────────────────────────────────────────────────────────────────────────────

struct CoachService {
    private let client = APIClient()

    func today(profile: UserProfile, timelineMonths: Int?, missedWeekday: String?) async -> TodayResponse {
        if AppConfig.useDemoData {
            return CoachEngine.today(profile: AppConfig.demoProfile,
                                     timelineMonths: AppConfig.demoTimelineMonths,
                                     missedWeekday: AppConfig.demoMissedWeekday,
                                     isDemo: true)
        }
        do {
            let body = CoachProfileRequest(profile: profile, timelineMonths: timelineMonths, missedWeekday: missedWeekday)
            return try await client.post("coach/today", body: body, authorized: false, as: TodayResponse.self)
        } catch {
            return CoachEngine.today(profile: profile, timelineMonths: timelineMonths,
                                     missedWeekday: missedWeekday, isDemo: false)
        }
    }

    func calculateTargets(profile: UserProfile, timelineMonths: Int?) async -> NutritionTargets {
        if AppConfig.useDemoData {
            return CoachEngine.nutrition(profile: AppConfig.demoProfile, timelineMonths: AppConfig.demoTimelineMonths)
        }
        do {
            let body = CoachProfileRequest(profile: profile, timelineMonths: timelineMonths)
            return try await client.post("coach/calculate-targets", body: body, authorized: false, as: NutritionTargets.self)
        } catch {
            return CoachEngine.nutrition(profile: profile, timelineMonths: timelineMonths)
        }
    }

    func generate(_ req: GenerateWorkoutRequest) async -> GeneratedWorkout {
        if !AppConfig.useDemoData,
           let w = try? await client.post("workouts/generate", body: req, authorized: false, as: GeneratedWorkout.self) {
            return w
        }
        return CoachEngine.generate(focus: req.focus, durationMin: req.durationMin,
                                    location: req.location, equipment: req.equipment,
                                    level: req.level, title: req.title)
    }

    func adjustWeek(strategy: String, missedWeekday: String?) async -> AdjustWeekResponse {
        if !AppConfig.useDemoData {
            let body = AdjustWeekRequest(strategy: strategy, missedWeekday: missedWeekday)
            if let r = try? await client.post("workouts/adjust-week", body: body, authorized: false, as: AdjustWeekResponse.self) {
                return r
            }
        }
        return CoachEngine.adjustWeek(missedWeekday: missedWeekday, strategy: strategy)
    }
}
