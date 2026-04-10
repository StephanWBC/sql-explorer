import Foundation

struct ERDColumn: Identifiable {
    let id = UUID()
    let name: String
    let dataType: String
    let isPrimaryKey: Bool
    let isForeignKey: Bool
    let isNullable: Bool
}

class ERDTable: Identifiable, ObservableObject {
    let id = UUID()
    let schema: String
    let name: String
    let columns: [ERDColumn]
    @Published var position: CGPoint

    var fullName: String { "\(schema).\(name)" }

    init(schema: String, name: String, columns: [ERDColumn], position: CGPoint = .zero) {
        self.schema = schema
        self.name = name
        self.columns = columns
        self.position = position
    }
}

struct ERDRelationship: Identifiable {
    let id = UUID()
    let name: String
    let fromTable: String
    let fromColumn: String
    let toTable: String
    let toColumn: String
}

struct ERDTableEntry: Identifiable, Hashable {
    let id = UUID()
    let schema: String
    let name: String
    var fullName: String { "\(schema).\(name)" }
}

/// Raw FK row cached per ERD session to avoid repeated queries
struct ForeignKeyRow {
    let parentTable: String       // "schema.table" that HAS the FK column
    let parentColumn: String
    let referencedTable: String   // "schema.table" being REFERENCED
    let referencedColumn: String
    let constraintName: String
}

/// A table not yet on canvas but FK-connected to one that is
struct ERDRelatedTable: Identifiable {
    let id = UUID()
    let schema: String
    let name: String
    let relatedToTable: String    // fullName of the canvas table it connects to
    let foreignKeyName: String
    let columnName: String        // the FK column involved
    let direction: Direction

    var fullName: String { "\(schema).\(name)" }

    enum Direction {
        case incoming   // this table references a canvas table (its FK → canvas table)
        case outgoing   // canvas table references this table (canvas FK → this table)
    }
}

@MainActor
class ERDSchema: ObservableObject {
    // Canvas state
    @Published var tables: [ERDTable] = []
    @Published var relationships: [ERDRelationship] = []

    // Related tables (FK-connected but not on canvas)
    @Published var relatedTables: [ERDRelatedTable] = []

    // Sidebar state
    @Published var availableTables: [ERDTableEntry] = []
    @Published var isLoadingTableList: Bool = true
    @Published var isAddingTable: Bool = false

    // Cached FK metadata (loaded once per ERD session)
    var cachedForeignKeys: [ForeignKeyRow]?

    // Connection info
    var databaseName: String = ""
    var serverFqdn: String = ""
    var connectionId: UUID?

    // Saved diagram tracking (nil = unsaved)
    var savedDiagramId: UUID?
    var savedDiagramName: String = ""

    var tablesOnCanvas: Set<String> {
        Set(tables.map(\.fullName))
    }

    /// Count of unique related tables per canvas table (for canvas badges)
    var relatedCountByTable: [String: Int] {
        let onCanvas = tablesOnCanvas
        let offCanvas = relatedTables.filter { !onCanvas.contains($0.fullName) }
        // Count unique related table names per canvas table
        var counts: [String: Set<String>] = [:]
        for rel in offCanvas {
            counts[rel.relatedToTable, default: []].insert(rel.fullName)
        }
        return counts.mapValues(\.count)
    }
}
