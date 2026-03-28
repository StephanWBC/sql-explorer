import SwiftUI

/// Global app state — shared across all views
@MainActor
class AppState: ObservableObject {
    @Published var connectionManager = ConnectionManager()
    @Published var connectionStore = ConnectionStore()
    @Published var authService = AuthService()
    @Published var queryService = QueryExecutionService()
    @Published var explorerService = ObjectExplorerService()

    @Published var activeConnectionId: UUID?
    @Published var statusMessage: String = "Ready"
    @Published var currentDatabase: String = ""

    // Object Explorer tree
    @Published var explorerNodes: [DatabaseObject] = []

    // Query tabs
    @Published var queryTabs: [QueryTab] = []
    @Published var selectedTabId: UUID?

    var selectedTab: QueryTab? {
        get { queryTabs.first { $0.id == selectedTabId } }
        set {
            if let tab = newValue, let idx = queryTabs.firstIndex(where: { $0.id == tab.id }) {
                queryTabs[idx] = tab
            }
        }
    }
}

struct QueryTab: Identifiable {
    let id: UUID = UUID()
    var title: String
    var sql: String = ""
    var result: QueryResult?
    var isExecuting: Bool = false
    var connectionId: UUID
    var database: String
}
