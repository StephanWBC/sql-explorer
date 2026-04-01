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

@MainActor
class ERDSchema: ObservableObject {
    // Canvas state
    @Published var tables: [ERDTable] = []
    @Published var relationships: [ERDRelationship] = []

    // Sidebar state
    @Published var availableTables: [ERDTableEntry] = []
    @Published var isLoadingTableList: Bool = true
    @Published var isAddingTable: Bool = false

    // Connection info
    var databaseName: String = ""
    var connectionId: UUID?

    var tablesOnCanvas: Set<String> {
        Set(tables.map(\.fullName))
    }
}
