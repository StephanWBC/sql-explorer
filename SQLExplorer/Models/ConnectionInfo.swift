import Foundation

enum ConnectionAuthType: String, Codable, CaseIterable, Identifiable {
    case sqlAuthentication = "SQL Authentication"
    case entraIdInteractive = "Entra ID Interactive"

    var id: String { rawValue }
}

struct ConnectionInfo: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String = ""
    var server: String = ""
    var port: Int = 1433
    var database: String = "master"
    var authType: ConnectionAuthType = .entraIdInteractive
    var username: String?
    var password: String?
    var tenantId: String?
    var trustServerCertificate: Bool = true
    var encrypt: Bool = true
}
