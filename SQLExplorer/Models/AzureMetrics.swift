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
    var interval: String {
        switch self {
        case .last1h:  return "PT1M"
        case .last6h:  return "PT5M"
        case .last24h: return "PT15M"
        case .last7d:  return "PT1H"
        }
    }
}

struct MetricDataPoint: Identifiable, Hashable {
    let timestamp: Date
    let average: Double?
    let maximum: Double?
    let total: Double?

    var id: Date { timestamp }

    /// First non-nil value in priority Average → Total → Maximum.
    var primaryValue: Double? { average ?? total ?? maximum }
}

struct MetricSeries: Identifiable {
    let metricName: String
    let displayName: String
    let unit: String
    let dataPoints: [MetricDataPoint]

    var id: String { metricName }

    var isPercentage: Bool { unit.lowercased() == "percent" }

    var latestValue: Double? {
        dataPoints.reversed().first { $0.primaryValue != nil }?.primaryValue
    }
}
