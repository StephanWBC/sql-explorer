import SwiftUI
import Charts

/// Single-metric time-series chart card.
///
/// Features:
/// - Hover ruler with exact timestamp + value at cursor (crucial when investigating spikes
///   over a wide window like 24h / 7d where axis ticks are too coarse to read precisely).
/// - Min / Avg / Max / P95 stats strip.
/// - Trend delta (% change vs. start of window) next to latest value.
/// - Threshold coloring for percentage metrics (amber > 75%, red > 90%).
/// - Click to expand into a larger focused view (reuses the same view with `isExpanded = true`).
struct MetricChartView: View {
    let series: MetricSeries
    var isExpanded: Bool = false
    var onExpand: (() -> Void)? = nil
    var onPinToggle: (() -> Void)? = nil
    var isPinned: Bool = false

    @State private var hoverPoint: MetricDataPoint?

    // MARK: - Formatting

    private func format(_ v: Double) -> String {
        if series.isPercentage { return String(format: "%.1f%%", v) }
        if abs(v - v.rounded()) < 0.001 { return String(format: "%.0f", v) }
        return String(format: "%.2f", v)
    }

    /// Headline value shown in the card header.
    /// - Gauges: current/latest value.
    /// - Counters: sum across the visible window (e.g. "47 connections").
    private var formattedHeadline: String {
        guard let v = series.headlineValue else { return "—" }
        return format(v)
    }

    /// Color for the line/area based on the latest value (percent metrics only).
    private var accent: Color {
        guard series.isPercentage, let v = series.latestValue else { return .accentColor }
        if v >= 90 { return .red }
        if v >= 75 { return .orange }
        return .accentColor
    }

    /// Trend delta: latest - first (absolute in metric units).
    /// Only shown for gauges — "trend" on a counter (events per bucket) is not meaningful.
    private var trend: (symbol: String, text: String, color: Color)? {
        guard series.kind == .gauge,
              let first = series.firstValue, let last = series.latestValue else { return nil }
        let delta = last - first
        // Hide ~zero trends to reduce noise.
        let threshold = series.isPercentage ? 0.5 : max(0.5, abs(first) * 0.01)
        guard abs(delta) >= threshold else { return nil }
        let up = delta > 0
        let sym = up ? "arrow.up.right" : "arrow.down.right"
        let text: String
        if series.isPercentage {
            text = String(format: "%+.1fpp", delta)
        } else if abs(delta - delta.rounded()) < 0.001 {
            text = String(format: "%+.0f", delta)
        } else {
            text = String(format: "%+.1f", delta)
        }
        // For most SQL metrics (CPU, IO, connections failed, deadlocks) rising = worse.
        // Deadlocks / failures already signal problem by existing — coloring by direction is
        // still broadly useful. Neutral gray avoids over-claiming semantics.
        let color: Color = up ? .orange : .green
        return (sym, text, color)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            statsRow
            chart
                .frame(height: isExpanded ? 360 : 160)
            if isExpanded, let peak = series.peakPoint, let v = series.plotValue(for: peak) {
                peakCallout(timestamp: peak.timestamp, value: v)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isPinned ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.15),
                              lineWidth: isPinned ? 1.0 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onExpand?() }
        .contextMenu {
            if let onExpand { Button("Expand") { onExpand() } }
            if let onPinToggle {
                Button(isPinned ? "Unpin" : "Pin to top") { onPinToggle() }
            }
            Divider()
            Button("Copy latest value") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(formattedHeadline, forType: .string)
            }
            Button("Copy CSV") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(csvString(), forType: .string)
            }
        }
    }

    // MARK: - Header / stats

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tint)
            }
            Text(series.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            if let trend {
                HStack(spacing: 2) {
                    Image(systemName: trend.symbol)
                        .font(.system(size: 9, weight: .semibold))
                    Text(trend.text)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                }
                .foregroundStyle(trend.color)
                .help("Change over the selected window (latest − earliest)")
            }

            Spacer()

            Text(formattedHeadline)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(.primary)

            if !isExpanded, onExpand != nil {
                Button {
                    onExpand?()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Expand")
            }
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        HStack(spacing: 10) {
            switch series.kind {
            case .gauge:
                // Classic Min/Avg/P95/Max over the window — what you want for %s and gauges.
                stat("Min", series.minValue)
                stat("Avg", series.avgValue)
                stat("P95", series.p95Value)
                stat("Max", series.maxValue)
            case .counter:
                // For counters the sum-over-window is already the headline; here we show
                // the biggest single bucket and the per-bucket average so you can see how
                // bursty the traffic is, plus the "latest bucket" as a current indicator.
                stat("Total", series.sumValue)
                stat("Peak/bucket", series.maxValue)
                stat("Avg/bucket", series.avgValue)
                stat("Latest", series.latestValue)
            }
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func stat(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.tertiary)
            Text(value.map(format) ?? "—").foregroundStyle(.secondary)
        }
    }

    private func peakCallout(timestamp: Date, value: Double) -> some View {
        let fmt = Date.FormatStyle(date: .abbreviated, time: .standard)
        return HStack(spacing: 6) {
            Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(.orange)
            Text("Peak \(format(value)) at \(timestamp.formatted(fmt))")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chart: some View {
        let base = Chart {
            ForEach(series.dataPoints) { point in
                if let v = series.plotValue(for: point) {
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value(series.displayName, v)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(accent)

                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value(series.displayName, v)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent.opacity(0.25), accent.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }

            if let hp = hoverPoint, let v = series.plotValue(for: hp) {
                RuleMark(x: .value("Time", hp.timestamp))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(
                    x: .value("Time", hp.timestamp),
                    y: .value(series.displayName, v)
                )
                .foregroundStyle(accent)
                .symbolSize(60)
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateHover(at: value.location, proxy: proxy, geo: geo)
                            }
                            .onEnded { _ in hoverPoint = nil }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            updateHover(at: location, proxy: proxy, geo: geo)
                        case .ended:
                            hoverPoint = nil
                        }
                    }

                if let hp = hoverPoint, let v = series.plotValue(for: hp),
                   let plotFrame = proxy.plotFrame.map({ geo[$0] }),
                   let x = proxy.position(forX: hp.timestamp) {
                    hoverTooltip(timestamp: hp.timestamp, value: v)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                        )
                        .shadow(radius: 2, y: 1)
                        .fixedSize()
                        .alignmentGuide(.leading) { d in
                            // Keep tooltip inside the plot area.
                            let desired = x + 10
                            let maxX = plotFrame.maxX - d.width - 4
                            let minX = plotFrame.minX + 4
                            return -min(max(desired, minX), maxX)
                        }
                        .alignmentGuide(.top) { _ in -(plotFrame.minY + 4) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                }
            }
        }

        if series.isPercentage {
            base.chartYScale(domain: 0.0...100.0)
        } else {
            base
        }
    }

    private func hoverTooltip(timestamp: Date, value: Double) -> some View {
        // Full precision — seconds included — so spikes over a 24h / 7d window can be
        // pinpointed from the chart alone.
        let fmt = Date.FormatStyle(date: .abbreviated, time: .standard)
        return VStack(alignment: .leading, spacing: 2) {
            Text(format(value))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(accent)
            Text(timestamp.formatted(fmt))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// Snap the cursor to the nearest data point — we only have sampled values
    /// from Azure Monitor, so interpolating between points would be misleading
    /// when debugging an actual sampled spike.
    private func updateHover(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame.map({ geo[$0] }) else { return }
        let xInPlot = location.x - plotFrame.origin.x
        guard xInPlot >= 0, xInPlot <= plotFrame.width else {
            hoverPoint = nil
            return
        }
        guard let date: Date = proxy.value(atX: xInPlot) else { return }
        // Nearest data point with a plottable value.
        let nearest = series.dataPoints
            .filter { series.plotValue(for: $0) != nil }
            .min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
        hoverPoint = nearest
    }

    // MARK: - CSV

    private func csvString() -> String {
        var lines = ["timestamp,value"]
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        for p in series.dataPoints {
            guard let v = series.plotValue(for: p) else { continue }
            lines.append("\(fmt.string(from: p.timestamp)),\(v)")
        }
        return lines.joined(separator: "\n")
    }
}
