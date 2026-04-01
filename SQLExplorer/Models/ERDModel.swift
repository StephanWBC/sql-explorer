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

@MainActor
class ERDSchema: ObservableObject {
    @Published var tables: [ERDTable] = []
    @Published var relationships: [ERDRelationship] = []
    @Published var databaseName: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
}
