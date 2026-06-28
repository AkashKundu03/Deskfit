import SwiftUI

/// Quick energy / soreness check-in from the wrist; relayed to the phone.
struct WatchCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var connectivity = WatchConnectivityManager.shared
    @State private var energy = 3
    @State private var soreness = 2

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                scale("Energy", $energy)
                scale("Soreness", $soreness)
                Button("Save") {
                    connectivity.send(WatchActionMessage(action: .checkIn, energy: energy, soreness: soreness))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Check-in")
    }

    private func scale(_ title: String, _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { n in
                    Button("\(n)") { value.wrappedValue = n }
                        .buttonStyle(.bordered)
                        .tint(value.wrappedValue == n ? .accentColor : nil)
                }
            }
        }
    }
}
