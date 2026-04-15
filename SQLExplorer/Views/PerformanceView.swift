import SwiftUI

@MainActor
final class PerformanceViewModel: ObservableObject {
    @Published var series: [MetricSeries] = []
    @Published var isLoading: Bool = false
    @Published var permissionDenied: Bool = false
    @Published var errorMessage: String?
    @Published var selectedTimeRange: MetricTimeRange = .last1h
    @Published var autoRefresh: Bool = false

    private var loadedDbId: AzureDatabase.ID?
    /// Metric names valid for the loaded resource (intersection of our defaults and
    /// what the resource's metricDefinitions endpoint returns). Cached after first load.
    private var availableMetricNames: [String] = []

    /// Full load: ARM token → fetch metric definitions (also serves as permission check) → fetch metrics.
    func load(db: AzureDatabase, authService: AuthService) async {
        isLoading = true
        permissionDenied = false
        errorMessage = nil
        defer { isLoading = false }

        guard let token = await authService.getARMToken() else {
            errorMessage = "Could not acquire Azure access token. Sign in again."
            return
        }

        let resourceId = AzureMetricsService.resourceId(for: db)
        let result = await AzureMetricsService.fetchMetricDefinitions(resourceId: resourceId, token: token)
        switch result {
        case .denied:
            permissionDenied = true
            return
        case .error(let msg):
            errorMessage = msg
            return
        case .allowed(let names):
            // Keep only metrics that (a) we know how to display and (b) actually exist on this resource.
            availableMetricNames = AzureMetricsService.defaultMetricNames.filter { names.contains($0) }
        }

        guard !availableMetricNames.isEmpty else {
            errorMessage = "No supported metrics are available for this resource."
            return
        }

        do {
            series = try await AzureMetricsService.fetchMetrics(
                resourceId: resourceId,
                token: token,
                timeRange: selectedTimeRange,
                metricNames: availableMetricNames)
            loadedDbId = db.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Lighter refresh: skips definitions/permission probe (only call after a successful `load`).
    func refresh(db: AzureDatabase, authService: AuthService) async {
        guard !isLoading else { return }
        // If db changed, do a full load instead.
        if loadedDbId != db.id || availableMetricNames.isEmpty {
            await load(db: db, authService: authService)
            return
        }
        guard let token = await authService.getARMToken() else { return }
        let resourceId = AzureMetricsService.resourceId(for: db)
        do {
            let fresh = try await AzureMetricsService.fetchMetrics(
                resourceId: resourceId,
                token: token,
                timeRange: selectedTimeRange,
                metricNames: availableMetricNames)
            series = fresh
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PerformanceView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = PerformanceViewModel()
    @State private var refreshTick: Int = 0
    @State private var expandedMetric: String?
    @AppStorage("performance.pinnedMetrics") private var pinnedRaw: String = ""

    private let columns = [GridItem(.adaptive(minimum: 360), spacing: 12)]
    private let autoRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var pinned: Set<String> {
        Set(pinnedRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private func togglePin(_ name: String) {
        var set = pinned
        if set.contains(name) { set.remove(name) } else { set.insert(name) }
        pinnedRaw = set.sorted().joined(separator: ",")
    }

    /// Pinned metrics first (preserving backend order inside each group).
    private var orderedSeries: [MetricSeries] {
        let pins = pinned
        return viewModel.series.sorted { a, b in
            let ap = pins.contains(a.metricName)
            let bp = pins.contains(b.metricName)
            if ap != bp { return ap && !bp }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: appState.performanceContext?.id) {
            guard let db = appState.performanceContext else { return }
            await viewModel.load(db: db, authService: appState.authService)
        }
        .onChange(of: viewModel.selectedTimeRange) { _, _ in
            Task {
                guard let db = appState.performanceContext else { return }
                await viewModel.refresh(db: db, authService: appState.authService)
            }
        }
        .onReceive(autoRefreshTimer) { _ in
            guard viewModel.autoRefresh, let db = appState.performanceContext else { return }
            Task { await viewModel.refresh(db: db, authService: appState.authService) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let db = appState.performanceContext {
                    Text(db.databaseName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(db.serverFqdn)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Performance")
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            Spacer()

            Picker("Time range", selection: $viewModel.selectedTimeRange) {
                ForEach(MetricTimeRange.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 160)

            Toggle(isOn: $viewModel.autoRefresh) {
                Text("Auto")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Refresh every 60 seconds")

            Button {
                Task {
                    guard let db = appState.performanceContext else { return }
                    await viewModel.refresh(db: db, authService: appState.authService)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoading || appState.performanceContext == nil)
            .help("Refresh now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if appState.performanceContext == nil {
            centeredMessage(
                icon: "chart.line.uptrend.xyaxis",
                title: "No database selected",
                detail: "Open this window from a connected Azure SQL Database in the Object Explorer."
            )
        } else if viewModel.isLoading && viewModel.series.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading metrics…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.permissionDenied {
            centeredMessage(
                icon: "lock.shield",
                title: "Permission required",
                detail: "Your Azure account doesn't have access to read metrics for this database.\n\nRequired role: Monitoring Reader (or any role granting Microsoft.Insights/metrics/read on the database resource)."
            )
        } else if let err = viewModel.errorMessage, viewModel.series.isEmpty {
            centeredMessage(icon: "exclamationmark.triangle", title: "Couldn't load metrics", detail: err)
        } else if viewModel.series.isEmpty {
            centeredMessage(
                icon: "chart.bar",
                title: "No metric data",
                detail: "Azure Monitor returned no points for the selected time range."
            )
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    HealthOverviewCard(
                        series: viewModel.series,
                        timeRangeLabel: viewModel.selectedTimeRange.rawValue
                    )

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(orderedSeries) { s in
                            MetricChartView(
                                series: s,
                                isExpanded: false,
                                onExpand: { expandedMetric = s.metricName },
                                onPinToggle: { togglePin(s.metricName) },
                                isPinned: pinned.contains(s.metricName)
                            )
                        }
                    }
                }
                .padding(14)
            }
            .overlay(alignment: .topTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                }
            }
            .sheet(item: Binding(
                get: { expandedMetric.flatMap { name in viewModel.series.first { $0.metricName == name } }.map { ExpandedMetric(series: $0) } },
                set: { expandedMetric = $0?.series.metricName }
            )) { expanded in
                ExpandedMetricSheet(series: expanded.series) { expandedMetric = nil }
            }
        }
    }

    private struct ExpandedMetric: Identifiable {
        let series: MetricSeries
        var id: String { series.metricName }
    }

    private func centeredMessage(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Expanded metric sheet

/// Full-size focused view of a single metric with CSV export. Reuses `MetricChartView`
/// (same rendering, same hover ruler, just a taller chart and extra toolbar actions).
private struct ExpandedMetricSheet: View {
    let series: MetricSeries
    let onClose: () -> Void

    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(series.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    exportCSV()
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                Button("Done", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
            }
            .padding(14)
            Divider()

            ScrollView {
                MetricChartView(series: series, isExpanded: true)
                    .padding(14)
            }
        }
        .frame(minWidth: 780, idealWidth: 960, minHeight: 520, idealHeight: 620)
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(series.metricName).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime]
            var lines = ["timestamp,average,total,maximum"]
            for p in series.dataPoints {
                let a = p.average.map { String($0) } ?? ""
                let t = p.total.map   { String($0) } ?? ""
                let m = p.maximum.map { String($0) } ?? ""
                lines.append("\(fmt.string(from: p.timestamp)),\(a),\(t),\(m)")
            }
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
