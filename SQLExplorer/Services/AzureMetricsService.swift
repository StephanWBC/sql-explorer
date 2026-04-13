import Foundation

/// Stateless wrapper around the Azure Monitor metrics REST API for Azure SQL Databases.
enum AzureMetricsService {

    /// Default metric set we display on the Performance window.
    /// Some metrics only exist on specific SKUs (e.g. `dtu_consumption_percent` only on DTU SKUs);
    /// the API silently omits those that don't apply, which we mirror — they just won't appear in the grid.
    private static let defaultMetricNames: [String] = [
        "cpu_percent",
        "dtu_consumption_percent",
        "physical_data_read_percent",
        "log_write_percent",
        "storage_percent",
        "workers_percent",
        "sessions_percent",
        "deadlock",
        "connection_successful",
        "connection_failed",
        "blocked_by_firewall"
    ]

    private static let displayNames: [String: String] = [
        "cpu_percent":                "CPU %",
        "dtu_consumption_percent":    "DTU %",
        "physical_data_read_percent": "Data IO %",
        "log_write_percent":          "Log IO %",
        "storage_percent":            "Storage %",
        "workers_percent":            "Workers %",
        "sessions_percent":           "Sessions %",
        "deadlock":                   "Deadlocks",
        "connection_successful":      "Successful Connections",
        "connection_failed":          "Failed Connections",
        "blocked_by_firewall":        "Blocked by Firewall"
    ]

    // MARK: - Resource ID

    static func resourceId(for db: AzureDatabase) -> String {
        let serverName = db.serverFqdn
            .replacingOccurrences(of: ".database.windows.net", with: "")
        return "/subscriptions/\(db.subscriptionId)" +
               "/resourceGroups/\(db.resourceGroup)" +
               "/providers/Microsoft.Sql/servers/\(serverName)" +
               "/databases/\(db.databaseName)"
    }

    // MARK: - Permission Probe

    /// Attempts a cheap `metricDefinitions` read to confirm the user has
    /// `Microsoft.Insights/metrics/read` on the resource. 200 = allowed, 401/403 = denied.
    /// Other failures (network, etc.) are treated as denied — the UI will surface the message.
    static func probePermission(resourceId: String, token: String) async -> Bool {
        let url = URL(string: "https://management.azure.com\(resourceId)/providers/Microsoft.Insights/metricDefinitions?api-version=2018-01-01")!
        var req = URLRequest(url: url)
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 200 { return true }
            AppLogger.metrics.warning("Permission probe HTTP \(http.statusCode)")
            return false
        } catch {
            AppLogger.metrics.warning("Permission probe failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Metrics

    static func fetchMetrics(resourceId: String,
                             token: String,
                             timeRange: MetricTimeRange) async throws -> [MetricSeries] {
        var components = URLComponents(string: "https://management.azure.com\(resourceId)/providers/Microsoft.Insights/metrics")!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "2018-01-01"),
            URLQueryItem(name: "metricnames", value: defaultMetricNames.joined(separator: ",")),
            URLQueryItem(name: "aggregation", value: "Average,Maximum,Total"),
            URLQueryItem(name: "timespan",    value: timeRange.timespan),
            URLQueryItem(name: "interval",    value: timeRange.interval)
        ]

        var req = URLRequest(url: components.url!)
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "AzureMetricsService", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Azure Monitor returned HTTP \(http.statusCode): \(body.prefix(200))"
            ])
        }

        return parseMetricsResponse(data)
    }

    // MARK: - Parsing

    /// Parses the Azure Monitor `metrics` response into our `MetricSeries` model.
    /// Response shape:
    /// ```
    /// {
    ///   "value": [{
    ///     "name": { "value": "cpu_percent", "localizedValue": "CPU percentage" },
    ///     "unit": "Percent",
    ///     "timeseries": [{
    ///       "data": [
    ///         { "timeStamp": "...", "average": 12.3, "maximum": 45.6 }
    ///       ]
    ///     }]
    ///   }]
    /// }
    /// ```
    private static func parseMetricsResponse(_ data: Data) -> [MetricSeries] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["value"] as? [[String: Any]] else { return [] }

        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFmtNoFrac = ISO8601DateFormatter()
        isoFmtNoFrac.formatOptions = [.withInternetDateTime]

        var series: [MetricSeries] = []
        for metric in values {
            guard let nameDict = metric["name"] as? [String: Any],
                  let metricName = nameDict["value"] as? String else { continue }
            let unit = metric["unit"] as? String ?? ""
            let display = displayNames[metricName] ?? (nameDict["localizedValue"] as? String ?? metricName)

            let timeseries = metric["timeseries"] as? [[String: Any]] ?? []
            var points: [MetricDataPoint] = []
            for ts in timeseries {
                let dataArr = ts["data"] as? [[String: Any]] ?? []
                for d in dataArr {
                    guard let tsStr = d["timeStamp"] as? String,
                          let date = isoFmt.date(from: tsStr) ?? isoFmtNoFrac.date(from: tsStr) else { continue }
                    let avg = d["average"] as? Double
                    let max = d["maximum"] as? Double
                    let total = d["total"] as? Double
                    // Skip points where every aggregation is missing — they're noise.
                    if avg == nil && max == nil && total == nil { continue }
                    points.append(MetricDataPoint(timestamp: date, average: avg, maximum: max, total: total))
                }
            }
            // Skip metrics that returned no usable points (e.g. dtu_consumption_percent on vCore SKUs).
            guard !points.isEmpty else { continue }
            points.sort { $0.timestamp < $1.timestamp }
            series.append(MetricSeries(metricName: metricName, displayName: display, unit: unit, dataPoints: points))
        }

        // Stable display order matching defaultMetricNames where possible.
        let order = Dictionary(uniqueKeysWithValues: defaultMetricNames.enumerated().map { ($1, $0) })
        series.sort { (order[$0.metricName] ?? Int.max) < (order[$1.metricName] ?? Int.max) }
        return series
    }
}
