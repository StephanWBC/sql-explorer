import Foundation

/// Plain-language documentation for a metric so the Performance view can explain
/// *what it is* and *when to worry* without the reader needing Azure Monitor knowledge.
///
/// `warnThreshold` / `critThreshold` are the bands used by the health overview and
/// the warning line overlays on charts. For percentage gauges these are the same
/// 75 % / 90 % bands used by the accent color in `MetricChartView`.
struct MetricInfo {
    /// One-line description of what the metric represents.
    let summary: String
    /// How to read the chart (which aggregation, which direction is bad).
    let interpretation: String
    /// What a junior dev should do / investigate if the metric looks bad.
    let whenToWorry: String
    /// Sustained-value warning threshold (in the metric's own units). `nil` for metrics
    /// that don't have a sensible universal threshold (e.g. successful connections).
    let warnThreshold: Double?
    /// Sustained-value critical threshold.
    let critThreshold: Double?
    /// If true, this metric contributes to the overall health score.
    let affectsHealth: Bool
}

enum MetricCatalog {
    /// Keyed by the Azure Monitor metric name (not the display name).
    static let all: [String: MetricInfo] = [
        "cpu_percent": MetricInfo(
            summary: "Percentage of the database's CPU budget being used.",
            interpretation: "100 % means the database is fully CPU-bound during that bucket — queries will queue and latency will spike. The chart plots the *maximum* per bucket so short spikes stay visible.",
            whenToWorry: "Sustained > 75 % → tune the top queries (sys.dm_exec_query_stats) or scale up the tier. Brief spikes to 100 % during reporting jobs are normal; flat-line 100 % is not.",
            warnThreshold: 75,
            critThreshold: 90,
            affectsHealth: true
        ),
        "dtu_consumption_percent": MetricInfo(
            summary: "DTU usage — blended CPU + IO + log score for DTU-tier databases.",
            interpretation: "Only present on DTU SKUs (Basic/Standard/Premium). 100 % means the database is at its DTU cap for that bucket.",
            whenToWorry: "Sustained > 80 % usually means it's time to move up a tier or migrate to vCore. Check whether CPU, Data IO, or Log IO is the dominant driver.",
            warnThreshold: 75,
            critThreshold: 90,
            affectsHealth: true
        ),
        "physical_data_read_percent": MetricInfo(
            summary: "Data file read throughput as a percentage of the tier's IO cap.",
            interpretation: "High values mean the database is doing a lot of physical reads from storage — typically caused by missing indexes, large table scans, or a cold buffer pool after a restart.",
            whenToWorry: "Sustained > 80 % combined with high CPU usually points to a missing index. Check the query store / missing-index DMVs.",
            warnThreshold: 75,
            critThreshold: 90,
            affectsHealth: true
        ),
        "log_write_percent": MetricInfo(
            summary: "Transaction log write throughput as a percentage of the tier's log rate limit.",
            interpretation: "Hits 100 % during heavy writes (bulk inserts, large updates, index rebuilds). Azure throttles log writes when this cap is reached — application writes will visibly slow down.",
            whenToWorry: "Sustained 100 % is the #1 cause of \"my inserts are slow after lunch\" complaints. Batch smaller, add a WAITFOR between batches, or scale the tier.",
            warnThreshold: 75,
            critThreshold: 90,
            affectsHealth: true
        ),
        "storage_percent": MetricInfo(
            summary: "Used data space as a percentage of the database's MAXSIZE.",
            interpretation: "Grows slowly; not a latency signal. A flat line is normal — a sudden jump is usually a bulk load or an un-shrunk log.",
            whenToWorry: "> 85 % → plan to increase MAXSIZE or archive/delete data. At 100 % all writes fail with error 40544.",
            warnThreshold: 80,
            critThreshold: 95,
            affectsHealth: true
        ),
        "workers_percent": MetricInfo(
            summary: "Active worker threads as a percentage of the tier's worker limit.",
            interpretation: "Each concurrent request uses at least one worker. Long-running or blocked queries consume workers without doing work.",
            whenToWorry: "Near 100 % → incoming requests get error 10928 (\"request limit reached\"). Usually means blocking chains or connection-pool leaks — check sys.dm_exec_requests.",
            warnThreshold: 75,
            critThreshold: 90,
            affectsHealth: true
        ),
        "sessions_percent": MetricInfo(
            summary: "Open sessions as a percentage of the tier's session limit.",
            interpretation: "Measures *connection* saturation, not *query* load. A high value with low CPU usually means idle connections piling up.",
            whenToWorry: "Trending upward over hours/days → a connection-pool leak in the app. Near 100 % → clients get error 10928.",
            warnThreshold: 75,
            critThreshold: 90,
            affectsHealth: true
        ),
        "deadlock": MetricInfo(
            summary: "Number of deadlocks detected in each time bucket.",
            interpretation: "A counter — the chart shows deadlocks *per bucket*, the headline is the total across the window. Zero is the expected value.",
            whenToWorry: "Any non-zero value deserves investigation — capture the deadlock graph via Extended Events. Recurring deadlocks almost always mean an index is missing or two code paths acquire locks in different orders.",
            warnThreshold: 1,
            critThreshold: 5,
            affectsHealth: true
        ),
        "connection_successful": MetricInfo(
            summary: "Number of successful logins per bucket.",
            interpretation: "Traffic indicator, not a health signal. Useful for spotting deploys (sudden drop/spike) and correlating load with performance.",
            whenToWorry: "Sudden drop to zero during business hours → the database likely isn't reachable. Correlate with failed-connection and blocked-by-firewall charts.",
            warnThreshold: nil,
            critThreshold: nil,
            affectsHealth: false
        ),
        "connection_failed": MetricInfo(
            summary: "Number of login failures per bucket.",
            interpretation: "Counts both auth failures and database-unavailable errors. A steady low rate usually comes from health probes or misconfigured clients.",
            whenToWorry: "Sharp spike → recent deploy broke a connection string, or a secret rotated. Slow creep upward over days → a client is retrying with stale credentials.",
            warnThreshold: 5,
            critThreshold: 50,
            affectsHealth: true
        ),
        "blocked_by_firewall": MetricInfo(
            summary: "Connection attempts rejected by the server-level firewall.",
            interpretation: "Should almost always be zero. Any non-zero value means a client tried to connect from an IP that isn't on the firewall allow-list.",
            whenToWorry: "Non-zero → either a legitimate client moved IPs (VPN / new office) or something is probing the server. Check the source IP in Azure audit logs.",
            warnThreshold: 1,
            critThreshold: 10,
            affectsHealth: true
        )
    ]

    static func info(for metricName: String) -> MetricInfo? { all[metricName] }
}

// MARK: - Health evaluation

/// Severity bucket a metric falls into *right now*, based on its catalog thresholds.
enum MetricSeverity: Int, Comparable {
    case ok = 0
    case warning = 1
    case critical = 2

    static func < (lhs: MetricSeverity, rhs: MetricSeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .ok: return "OK"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

/// A single issue detected on one metric — feeds the health overview's "top issues" list.
struct HealthFinding: Identifiable {
    let metricName: String
    let displayName: String
    let severity: MetricSeverity
    /// Human-readable explanation, e.g. "peaked at 100 %, averaged 62 %".
    let detail: String
    var id: String { metricName }
}

extension MetricSeries {
    /// Evaluate the current state of this series against its catalog thresholds.
    /// For gauges we weigh the P95 (sustained badness) and the peak equally — a brief
    /// spike to 100 % shouldn't count the same as sitting at 100 % for hours, which is
    /// why thresholds are checked against both P95 *and* peak, and we take the worst.
    func evaluateHealth() -> HealthFinding? {
        guard let info = MetricCatalog.info(for: metricName), info.affectsHealth else { return nil }

        switch kind {
        case .gauge:
            guard let p95 = p95Value, let peak = maxValue else { return nil }
            let severity = gaugeSeverity(p95: p95, peak: peak, info: info)
            guard severity != .ok else { return nil }
            let detail: String
            if isPercentage {
                detail = String(format: "peaked at %.0f %%, sustained %.0f %% (P95)", peak, p95)
            } else {
                detail = String(format: "peaked at %.1f, sustained %.1f (P95)", peak, p95)
            }
            return HealthFinding(metricName: metricName, displayName: displayName,
                                 severity: severity, detail: detail)
        case .counter:
            guard let total = sumValue, total > 0 else { return nil }
            let severity = counterSeverity(total: total, info: info)
            guard severity != .ok else { return nil }
            let detail = String(format: "%.0f total in this window", total)
            return HealthFinding(metricName: metricName, displayName: displayName,
                                 severity: severity, detail: detail)
        }
    }

    private func gaugeSeverity(p95: Double, peak: Double, info: MetricInfo) -> MetricSeverity {
        var worst: MetricSeverity = .ok
        if let crit = info.critThreshold {
            // Sustained P95 past critical, OR peak pegged at the cap for a % metric.
            if p95 >= crit { worst = max(worst, .critical) }
            if isPercentage && peak >= 99 { worst = max(worst, .critical) }
        }
        if let warn = info.warnThreshold {
            if p95 >= warn { worst = max(worst, .warning) }
            if isPercentage && peak >= warn + 10 { worst = max(worst, .warning) }
        }
        return worst
    }

    private func counterSeverity(total: Double, info: MetricInfo) -> MetricSeverity {
        if let crit = info.critThreshold, total >= crit { return .critical }
        if let warn = info.warnThreshold, total >= warn { return .warning }
        return .ok
    }
}

private func max(_ a: MetricSeverity, _ b: MetricSeverity) -> MetricSeverity {
    a > b ? a : b
}
