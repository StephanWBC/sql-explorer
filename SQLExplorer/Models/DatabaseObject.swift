import Foundation

enum DatabaseObjectType: String, Codable {
    case server
    case connectionGroup
    case database
    case folder
    case table
    case view
    case storedProcedure
    case function
    case column
    case index
    case foreignKey
    case primaryKey
    case trigger
}

class DatabaseObject: Identifiable, ObservableObject {
    let id: UUID = UUID()
    var name: String
    var schema: String
    var database: String
    var connectionId: UUID?
    var objectType: DatabaseObjectType
    var isExpandable: Bool
    @Published var isLoaded: Bool = false
    @Published var children: [DatabaseObject] = []

    init(
        name: String,
        schema: String = "dbo",
        database: String = "",
        connectionId: UUID? = nil,
        objectType: DatabaseObjectType = .folder,
        isExpandable: Bool = false
    ) {
        self.name = name
        self.schema = schema
        self.database = database
        self.connectionId = connectionId
        self.objectType = objectType
        self.isExpandable = isExpandable
    }

    var icon: String {
        switch objectType {
        case .server: return "desktopcomputer"
        case .connectionGroup: return "folder.fill"
        case .database: return "cylinder"
        case .folder: return "folder"
        case .table: return "tablecells"
        case .view: return "eye"
        case .storedProcedure: return "gearshape"
        case .function: return "function"
        case .column: return "line.3.horizontal"
        case .index: return "arrow.up.arrow.down"
        case .foreignKey: return "link"
        case .primaryKey: return "key"
        case .trigger: return "bolt"
        }
    }
}
