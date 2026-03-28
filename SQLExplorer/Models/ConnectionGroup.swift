import Foundation

struct ConnectionGroup: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    var isExpanded: Bool = true
}
