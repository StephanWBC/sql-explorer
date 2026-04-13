import SwiftUI
import Charts

/// Single-metric time-series chart card.
struct MetricChartView: View {
    let series: MetricSeries

    private var formattedLatest: String {
        guard let v = series.latestValue else { return "—" }
        if series.isPercentage {
            return String(format: "%.1f%%", v)
        }
        // Counts (deadlocks, connections) — round
        if abs(v - v.rounded()) < 0.001 {
            return String(format: "%.0f", v)
        }
        return String(format: "%.2f", v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(series.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(formattedLatest)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            chart
                .frame(height: 160)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var chart: some View {
        let base = Chart {
            ForEach(series.dataPoints) { point in
                if let v = point.primaryValue {
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value(series.displayName, v)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)

                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value(series.displayName, v)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel().font(.system(size: 9))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.1))
                AxisValueLabel(format: .dateTime.hour().minute()).font(.system(size: 9))
            }
        }

        if series.isPercentage {
            base.chartYScale(domain: 0.0...100.0)
        } else {
            base
        }
    }
}
