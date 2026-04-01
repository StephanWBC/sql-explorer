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
    let fromTable: String   // "schema.table"
    let fromColumn: String
    let toTable: String     // "schema.table"
    let toColumn: String
}

/// Lightweight table name for the picker (before loading full schema)
struct ERDTableEntry: Identifiable, Hashable {
    let id = UUID()
    let schema: String
    let name: String
    var fullName: String { "\(schema).\(name)" }
}

enum ERDPhase {
    case pickingTables      // showing table picker
    case loading            // fetching schema for selected tables
    case ready              // diagram ready
    case error(String)      // failed
}

@MainActor
class ERDSchema: ObservableObject {
    @Published var tables: [ERDTable] = []
    @Published var relationships: [ERDRelationship] = []
    @Published var databaseName: String = ""
    @Published var connectionId: UUID?
    @Published var phase: ERDPhase = .pickingTables

    // Table picker state
    @Published var availableTables: [ERDTableEntry] = []
    @Published var selectedTableNames: Set<String> = []  // "schema.table" strings
}
