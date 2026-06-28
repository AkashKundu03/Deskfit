import SwiftUI

struct WatchWorkoutView: View {
    let workout: WatchWorkout

    @Environment(\.dismiss) private var dismiss
    @State private var manager = WorkoutManager()
    @State private var connectivity = WatchConnectivityManager.shared
    @State private var started = false
    @State private var exerciseIndex = 0

    var body: some View {
        TabView {
            metricsTab.tag(0)
            exercisesTab.tag(1)
            controlsTab.tag(2)
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !started {
                started = true
                _ = await manager.requestAuthorization()
                manager.start()
            }
        }
    }

    private var metricsTab: some View {
        VStack(spacing: 8) {
            metric("\(Int(manager.heartRate))", "bpm", "heart.fill", .red)
            HStack {
                metric("Z\(manager.zone)", "zone", "bolt.heart.fill", .orange)
                metric("\(Int(manager.activeEnergyKcal))", "kcal", "flame.fill", .orange)
            }
            Text(timeString(manager.elapsed)).font(.system(.title2, design: .rounded).monospacedDigit())
        }
        .padding(.horizontal, 6)
    }

    private var exercisesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Exercises").font(.caption2).foregroundStyle(.secondary)
                ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { idx, ex in
                    HStack {
                        Image(systemName: idx < exerciseIndex ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(idx < exerciseIndex ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(ex.name).font(.caption)
                            Text(ex.detail).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Next exercise") {
                    if exerciseIndex < workout.exercises.count { exerciseIndex += 1 }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 6)
        }
    }

    private var controlsTab: some View {
        VStack(spacing: 8) {
            if manager.isPaused {
                Button { manager.resume() } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { manager.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(.bordered)
            }
            Button(role: .destructive) { finish() } label: { Label("Finish", systemImage: "stop.fill") }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 6)
    }

    private func metric(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.system(.title3, design: .rounded).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func finish() {
        manager.end()
        connectivity.send(WatchActionMessage(
            action: .completeWorkout,
            workoutMinutes: Int(manager.elapsed / 60),
            activeEnergyKcal: Int(manager.activeEnergyKcal)))
        dismiss()
    }

    private func timeString(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
