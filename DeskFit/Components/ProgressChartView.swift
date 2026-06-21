import SwiftUI

/// Friendly, animated projection chart. Axes draw first, then the projected
/// line, then the markers fade in. Custom SwiftUI Paths (not Swift Charts) so the
/// drawing animation is fully controllable. Labels stay plain: Start / Today / Goal.
struct ProgressChartView: View {
    let projection: ProgressProjection

    @State private var axisProgress: CGFloat = 0
    @State private var lineProgress: CGFloat = 0
    @State private var markersIn = false

    private let chartHeight: CGFloat = 180
    private let leftPad: CGFloat = 8
    private let bottomPad: CGFloat = 28

    private var minWeight: Double {
        (projection.points.min() ?? projection.targetWeight) - 1
    }
    private var maxWeight: Double {
        (projection.points.max() ?? projection.startWeight) + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your projected path", systemImage: "chart.xyaxis.line")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))

            chart
                .frame(height: chartHeight)

            labelsRow

            Text(projection.summary)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            if let note = projection.timelineNote {
                Label(note, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(Theme.workoutAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            statChips

            howItWorks
        }
        .onAppear(perform: animate)
    }

    // MARK: - Chart canvas

    private var chart: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let plotH = geo.size.height - bottomPad

            ZStack(alignment: .topLeading) {
                // Axes (drawn first).
                Path { p in
                    p.move(to: CGPoint(x: leftPad, y: 0))
                    p.addLine(to: CGPoint(x: leftPad, y: plotH))
                    p.addLine(to: CGPoint(x: w, y: plotH))
                }
                .trim(from: 0, to: axisProgress)
                .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                // Goal reference line (dashed horizontal at target weight).
                let goalY = yPos(projection.targetWeight, plotH: plotH)
                Path { p in
                    p.move(to: CGPoint(x: leftPad, y: goalY))
                    p.addLine(to: CGPoint(x: w, y: goalY))
                }
                .trim(from: 0, to: axisProgress)
                .stroke(Theme.secondaryAccent.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // Projected line (drawn after axes).
                projectedPath(width: w, plotH: plotH)
                    .trim(from: 0, to: lineProgress)
                    .stroke(
                        LinearGradient(colors: [Theme.primaryAccent, Theme.primaryAccentBlue],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: Theme.primaryAccent.opacity(0.45), radius: 6, y: 2)

                // Soft fill under the line.
                areaPath(width: w, plotH: plotH)
                    .fill(LinearGradient(colors: [Theme.primaryAccent.opacity(0.20), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(lineProgress)

                // Markers.
                if markersIn {
                    marker(at: pointPos(0, width: w, plotH: plotH), label: "Today", color: Theme.primaryAccent, filled: true)
                    marker(at: pointPos(projection.points.count - 1, width: w, plotH: plotH),
                           label: "Goal", color: Theme.success, filled: false)
                }
            }
        }
    }

    private func projectedPath(width: CGFloat, plotH: CGFloat) -> Path {
        Path { p in
            for (i, _) in projection.points.enumerated() {
                let pt = pointPos(i, width: width, plotH: plotH)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }

    private func areaPath(width: CGFloat, plotH: CGFloat) -> Path {
        Path { p in
            guard !projection.points.isEmpty else { return }
            p.move(to: CGPoint(x: leftPad, y: plotH))
            for (i, _) in projection.points.enumerated() {
                p.addLine(to: pointPos(i, width: width, plotH: plotH))
            }
            p.addLine(to: CGPoint(x: width, y: plotH))
            p.closeSubpath()
        }
    }

    private func pointPos(_ index: Int, width: CGFloat, plotH: CGFloat) -> CGPoint {
        let count = max(1, projection.points.count - 1)
        let x = leftPad + (width - leftPad) * CGFloat(index) / CGFloat(count)
        return CGPoint(x: x, y: yPos(projection.points[index], plotH: plotH))
    }

    private func yPos(_ weight: Double, plotH: CGFloat) -> CGFloat {
        let span = max(0.1, maxWeight - minWeight)
        let ratio = (weight - minWeight) / span
        return plotH * (1 - CGFloat(ratio))
    }

    private func marker(at point: CGPoint, label: String, color: Color, filled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(filled ? color : Color.black)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(color, lineWidth: 2))
                .shadow(color: color.opacity(0.6), radius: 5)
        }
        .position(point)
        .transition(.scale.combined(with: .opacity))
    }

    private var labelsRow: some View {
        HStack {
            chartLabel("Start", String(format: "%.0f kg", projection.startWeight))
            Spacer()
            chartLabel("Goal", String(format: "%.0f kg", projection.targetWeight), alignTrailing: true)
        }
    }

    private func chartLabel(_ title: String, _ value: String, alignTrailing: Bool = false) -> some View {
        VStack(alignment: alignTrailing ? .trailing : .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.55))
            Text(value).font(.caption.weight(.bold)).foregroundStyle(.white).monospacedDigit()
        }
    }

    private var statChips: some View {
        HStack(spacing: 8) {
            statChip(projection.isLoss ? "Weekly loss" : "Weekly gain",
                     String(format: "%.1f kg", projection.weeklyChangeKg))
            statChip("Daily target", "−\(projection.plannedDailyDeficit)")
            statChip("Workouts", "\(Int((projection.workoutConsistency * 100).rounded()))%")
            statChip("Meals", "\(Int((projection.mealConsistency * 100).rounded()))%")
        }
    }

    private func statChip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.caption.weight(.bold)).foregroundStyle(.white).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }

    private var howItWorks: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text("We start from your current and target weight, then estimate a weekly change from your planned daily calorie target and how consistently you complete workouts and meals.")
                Text("Nutrition is weighted more than training because it moves weight faster. \(projection.consistencyAssumed ? "We're using a gentle default consistency until you log a few days." : "These numbers update as you complete plans.")")
                Text("This is an educational projection, not a medical prediction.")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.top, 8)
        } label: {
            Text("How this projection works")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
        }
        .tint(Theme.accent)
    }

    // MARK: - Animation

    private func animate() {
        axisProgress = 0; lineProgress = 0; markersIn = false
        withAnimation(.easeInOut(duration: 0.5)) { axisProgress = 1 }
        withAnimation(.easeInOut(duration: 0.9).delay(0.5)) { lineProgress = 1 }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(1.3)) { markersIn = true }
    }
}
