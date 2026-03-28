import Foundation

struct SavedConnection: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String = ""
    var server: String = ""
    var port: Int = 1433
    var database: String = "master"
    var authType: ConnectionAuthType = .entraIdInteractive
    var username: String?
    var tenantId: String?
    var trustServerCertificate: Bool = true
    var encrypt: Bool = true
    var lastConnected: Date = Date()
    var groupId: UUID?
    var environmentLabel: String?
}
