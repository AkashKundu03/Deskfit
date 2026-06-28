import SwiftUI

struct WatchHomeView: View {
    @State private var connectivity = WatchConnectivityManager.shared
    @State private var showCheckIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let snap = connectivity.snapshot {
                        workoutSection(snap)
                        mealsSection(snap)
                    } else {
                        Text("Open DeskFit on your iPhone to sync today’s plan.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button { showCheckIn = true } label: {
                        Label("Quick check-in", systemImage: "checklist")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("DeskFit")
            .sheet(isPresented: $showCheckIn) { WatchCheckInView() }
        }
    }

    @ViewBuilder private func workoutSection(_ snap: WatchSnapshot) -> some View {
        if let w = snap.workout {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today’s workout").font(.caption2).foregroundStyle(.secondary)
                Text(w.title).font(.headline)
                Text("\(w.durationMin) min · \(w.focusLabel)").font(.caption2).foregroundStyle(.secondary)
                NavigationLink {
                    WatchWorkoutView(workout: w)
                } label: {
                    Label("Start workout", systemImage: "figure.run")
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            Text("Rest day — no workout scheduled.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func mealsSection(_ snap: WatchSnapshot) -> some View {
        if !snap.meals.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Meals").font(.caption2).foregroundStyle(.secondary)
                ForEach(snap.meals) { meal in
                    HStack {
                        Image(systemName: meal.status == "completed" ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(meal.status == "completed" ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(meal.slot.capitalized).font(.caption)
                            Text("\(meal.kcal) kcal").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if meal.status != "completed" {
                            Button("Done") {
                                connectivity.send(WatchActionMessage(action: .completeMeal, mealId: meal.id))
                            }
                            .buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                }
            }
        }
    }
}
