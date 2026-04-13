import Foundation

/// Time range for Azure Monitor metric queries.
enum MetricTimeRange: String, CaseIterable, Identifiable {
    case last1h  = "Last 1 hour"
    case last6h  = "Last 6 hours"
    case last24h = "Last 24 hours"
    case last7d  = "Last 7 days"

    var id: String { rawValue }

    /// ISO-8601 timespan `start/end` string for the Azure Monitor `timespan` query parameter.
    var timespan: String {
        let now = Date()
        let start: Date
        switch self {
        case .last1h:  start = now.addingTimeInterval(-3600)
        case .last6h:  start = now.addingTimeInterval(-6 * 3600)
        case .last24h: start = now.addingTimeInterval(-24 * 3600)
        case .last7d:  start = now.addingTimeInterval(-7 * 24 * 3600)
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return "\(fmt.string(from: start))/\(fmt.string(from: now))"
    }

    /// ISO-8601 duration suitable for the time range.
    /// Kept tight (smaller buckets = less smoothing) so peaks survive aggregation.
    var interval: String {
        switch self {
        case .last1h:  return "PT1M"
        case .last6h:  return "PT5M"
        case .last24h: return "PT5M"
        case .last7d:  return "PT30M"
        }
    }
}

/// How a metric's value should be interpreted.
///
/// Azure Monitor returns Average / Maximum / Total for every datapoint, but the *meaningful*
/// aggregation differs per metric:
/// - **Gauges** are instantaneous % or counts (CPU %, Log IO %, storage %). The portal plots
///   the `maximum` per bucket so spikes are visible. The headline is the latest reading.
/// - **Counters** are events-per-interval (successful connections, deadlocks). The `total`
///   per bucket is the count in that bucket; the window total is the sum across all buckets.
enum MetricKind {
    case gauge
    case counter
}

struct MetricDataPoint: Identifiable, Hashable {
    let timestamp: Date
    let average: Double?
    let maximum: Double?
    let total: Double?

    var id: Date { timestamp }
}

struct MetricSeries: Identifiable {
    let metricName: String
    let displayName: String
    let unit: String
    let dataPoints: [MetricDataPoint]

    var id: String { metricName }

    var isPercentage: Bool { unit.lowercased() == "percent" }

    /// Classifies a metric by name. Counters are Azure SQL's count-type metrics where
    /// the sum-over-window is what the user actually wants to see.
    var kind: MetricKind {
        switch metricName {
        case "deadlock", "connection_successful", "connection_failed", "blocked_by_firewall":
            return .counter
        default:
            return .gauge
        }
    }

    /// The value to plot for this point given the metric's kind.
    /// - Gauges: `maximum` (matches the Azure Portal's default aggregation). Falls back to
    ///   `average` if `maximum` is missing.
    /// - Counters: `total` (events in the bucket). Nil buckets are treated as 0 for
    ///   counters so the chart doesn't render gaps during quiet periods.
    func plotValue(for point: MetricDataPoint) -> Double? {
        switch kind {
        case .gauge:
            return point.maximum ?? point.average
        case .counter:
            return point.total ?? 0
        }
    }

    /// All plotted values (nil buckets dropped for gauges, treated as 0 for counters).
    var values: [Double] {
        dataPoints.compactMap { plotValue(for: $0) }
    }

    /// Latest non-nil plotted value — used as the "current" reading for gauges.
    var latestValue: Double? {
        dataPoints.reversed().compactMap { plotValue(for: $0) }.first
    }

    /// First non-nil plotted value — used for trend delta on gauges.
    var firstValue: Double? {
        dataPoints.compactMap { plotValue(for: $0) }.first
    }

    /// Sum of all plotted values. For counters this is the total events in the window.
    var sumValue: Double? {
        let v = values
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +)
    }

    var minValue: Double? { values.min() }
    var maxValue: Double? { values.max() }
    var avgValue: Double? {
        let v = values
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }

    /// 95th percentile (nearest-rank).
    var p95Value: Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let rank = Int((0.95 * Double(sorted.count)).rounded(.up)) - 1
        return sorted[max(0, min(sorted.count - 1, rank))]
    }

    /// Data point with the maximum plotted value (useful for debugging spikes).
    var peakPoint: MetricDataPoint? {
        dataPoints
            .compactMap { p -> (MetricDataPoint, Double)? in
                guard let v = plotValue(for: p) else { return nil }
                return (p, v)
            }
            .max(by: { $0.1 < $1.1 })?.0
    }

    /// Headline (big number in the card header):
    /// - Gauges: current value (latest reading)
    /// - Counters: sum across the visible window (e.g. "47 connections in 24h")
    var headlineValue: Double? {
        switch kind {
        case .gauge:   return latestValue
        case .counter: return sumValue
        }
    }
}
