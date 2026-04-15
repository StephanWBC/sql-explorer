import SwiftUI

/// Top-of-page summary that distills the current metric grid into a single verdict
/// (Healthy / Warning / Critical) and a list of detected issues. The goal is that a
/// junior dev can glance at this card and know whether to dig deeper, without reading
/// each chart individually.
struct HealthOverviewCard: View {
    let series: [MetricSeries]
    let timeRangeLabel: String

    /// All findings, sorted worst-first. Computed once per render.
    private var findings: [HealthFinding] {
        series
            .compactMap { $0.evaluateHealth() }
            .sorted { $0.severity > $1.severity }
    }

    /// Overall verdict is the worst individual finding.
    private var overallSeverity: MetricSeverity {
        findings.map(\.severity).max() ?? .ok
    }

    private var verdictTitle: String {
        switch overallSeverity {
        case .ok:       return "Healthy"
        case .warning:  return "Needs attention"
        case .critical: return "Critical issues detected"
        }
    }

    private var verdictSubtitle: String {
        switch overallSeverity {
        case .ok:
            return "No metric is over its warning threshold in the \(timeRangeLabel.lowercased())."
        case .warning:
            return "\(findings.count) metric\(findings.count == 1 ? "" : "s") crossed a warning threshold. Likely fine, but worth investigating."
        case .critical:
            let crit = findings.filter { $0.severity == .critical }.count
            return "\(crit) critical and \(findings.count - crit) warning issue\(findings.count - crit == 1 ? "" : "s") in the \(timeRangeLabel.lowercased()). Investigate now."
        }
    }

    private var verdictColor: Color {
        switch overallSeverity {
        case .ok:       return .green
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    private var verdictIcon: String {
        switch overallSeverity {
        case .ok:       return "checkmark.seal.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            verdictHeader
            if !findings.isEmpty {
                Divider()
                findingsList
            }
            Divider()
            kpiStrip
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(verdictColor.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Verdict header

    private var verdictHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: verdictIcon)
                .font(.system(size: 22))
                .foregroundStyle(verdictColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(verdictTitle)
                        .font(.system(size: 14, weight: .semibold))
                    Text("• \(timeRangeLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(verdictSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: - Findings

    private var findingsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DETECTED ISSUES")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.6)

            ForEach(findings) { f in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(f.severity == .critical ? Color.red : Color.orange)
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(f.displayName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(f.severity.label.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(f.severity == .critical ? Color.red : Color.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().stroke(
                                        f.severity == .critical ? Color.red.opacity(0.6) : Color.orange.opacity(0.6),
                                        lineWidth: 0.5
                                    )
                                )
                        }
                        Text(f.detail)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let info = MetricCatalog.info(for: f.metricName) {
                            Text(info.whenToWorry)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - KPI strip

    /// Key at-a-glance numbers for the most load-bearing metrics. Rendered even when
    /// there are no findings — gives the user a quick snapshot of the workload shape.
    private var kpiStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KEY INDICATORS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.6)

            HStack(spacing: 14) {
                kpi(for: "cpu_percent", label: "CPU")
                kpi(for: "log_write_percent", label: "Log IO")
                kpi(for: "physical_data_read_percent", label: "Data IO")
                kpi(for: "storage_percent", label: "Storage", mode: .current)
                kpi(for: "workers_percent", label: "Workers")
                kpi(for: "sessions_percent", label: "Sessions")
                kpiCount(for: "deadlock", label: "Deadlocks")
                kpiCount(for: "connection_failed", label: "Failed conns")
                Spacer()
            }
        }
    }

    private enum KPIMode { case p95, current }

    private func kpi(for metricName: String, label: String, mode: KPIMode = .p95) -> some View {
        let s = series.first(where: { $0.metricName == metricName })
        let primary: Double?
        let secondary: Double?
        switch mode {
        case .p95:
            primary = s?.p95Value
            secondary = s?.maxValue
        case .current:
            primary = s?.latestValue
            secondary = nil
        }

        let info = MetricCatalog.info(for: metricName)
        let tint = threshTint(primary: primary, info: info)

        return VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                Text(primary.map { formatPercent($0) } ?? "—")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                if let m = secondary, mode == .p95 {
                    Text("/ \(formatPercent(m))")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            Text(mode == .p95 ? "P95 / peak" : "current")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .help(kpiHelp(label: label, metricName: metricName, mode: mode))
    }

    private func kpiCount(for metricName: String, label: String) -> some View {
        let s = series.first(where: { $0.metricName == metricName })
        let total = s?.sumValue ?? 0
        let info = MetricCatalog.info(for: metricName)
        let severity: MetricSeverity = {
            if let crit = info?.critThreshold, total >= crit { return .critical }
            if let warn = info?.warnThreshold, total >= warn { return .warning }
            return .ok
        }()
        let tint: Color = severity == .critical ? .red : (severity == .warning ? .orange : .primary)

        return VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(String(format: "%.0f", total))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text("total")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .help(kpiHelp(label: label, metricName: metricName, mode: .p95))
    }

    private func threshTint(primary: Double?, info: MetricInfo?) -> Color {
        guard let v = primary, let info else { return .primary }
        if let c = info.critThreshold, v >= c { return .red }
        if let w = info.warnThreshold, v >= w { return .orange }
        return .primary
    }

    private func formatPercent(_ v: Double) -> String { String(format: "%.0f%%", v) }

    private func kpiHelp(label: String, metricName: String, mode: KPIMode) -> String {
        let base: String
        switch mode {
        case .p95:     base = "P95 / peak across the \(timeRangeLabel.lowercased())."
        case .current: base = "Most recent reading."
        }
        if let info = MetricCatalog.info(for: metricName) {
            return "\(base)\n\n\(info.summary)"
        }
        return base
    }
}
