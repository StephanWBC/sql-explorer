import Foundation
import os

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
    /// Lock-protected storage — never access directly, use `completions` accessor
    nonisolated(unsafe) private static var _completions: [String] = []
    nonisolated(unsafe) private static var _lock = os_unfair_lock()

    /// Thread-safe read access to the completion list
    static var completions: [String] {
        os_unfair_lock_lock(&_lock)
        let snapshot = _completions
        os_unfair_lock_unlock(&_lock)
        return snapshot
    }

    /// Keywords + schema objects combined
    @MainActor
    static func rebuild(schema: SchemaCache) {
        var items: [String] = []

        // SQL keywords
        items.append(contentsOf: sqlKeywords.map { $0.uppercased() })

        // Schema objects
        items.append(contentsOf: schema.tables)
        items.append(contentsOf: schema.views)
        items.append(contentsOf: schema.storedProcedures)
        items.append(contentsOf: schema.functions)

        let sorted = items.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        os_unfair_lock_lock(&_lock)
        _completions = sorted
        os_unfair_lock_unlock(&_lock)
    }
}
