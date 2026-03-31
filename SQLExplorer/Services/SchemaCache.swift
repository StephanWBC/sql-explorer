import Foundation

/// Shared cache of database schema for IntelliSense completions
@MainActor
class SchemaCache: ObservableObject {
    /// All known object names across all connected databases
    /// Format: "schema.name" (e.g. "dbo.Leads", "BLMS.LeadHistory")
    @Published var tables: [String] = []
    @Published var views: [String] = []
    @Published var storedProcedures: [String] = []
    @Published var functions: [String] = []

    /// Combined list for quick lookup
    var allObjects: [String] {
        tables + views + storedProcedures + functions
    }

    /// Update cache from explorer tree nodes
    func updateFromExplorerNodes(_ nodes: [DatabaseObject]) {
        var newTables: [String] = []
        var newViews: [String] = []
        var newProcs: [String] = []
        var newFuncs: [String] = []

        for server in nodes {
            for db in server.children where db.objectType == .database && db.isConnected {
                for folder in db.children {
                    for item in folder.children {
                        switch folder.name {
                        case "Tables": newTables.append(item.name)
                        case "Views": newViews.append(item.name)
                        case "Stored Procedures": newProcs.append(item.name)
                        case "Functions": newFuncs.append(item.name)
                        default: break
                        }
                    }
                }
            }
        }

        tables = newTables.sorted()
        views = newViews.sorted()
        storedProcedures = newProcs.sorted()
        functions = newFuncs.sorted()
    }
}

/// Static completion list accessible from any thread (for NSTextView delegate)
enum CompletionProvider {
    /// Thread-safe snapshot of completions — set from main thread, read from any
    nonisolated(unsafe) static var completions: [String] = []

    /// Keywords + schema objects combined
    @MainActor
    static func rebuild(schema: SchemaCache) {
        var items: [String] = []

        // SQL keywords (lowercase for nicer display)
        items.append(contentsOf: sqlKeywords.map { $0.uppercased() })

        // Schema objects
        items.append(contentsOf: schema.tables)
        items.append(contentsOf: schema.views)
        items.append(contentsOf: schema.storedProcedures)
        items.append(contentsOf: schema.functions)

        completions = items.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
