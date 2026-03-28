import Foundation

struct AzureSubscription: Identifiable, Hashable {
    let id: String      // subscriptionId GUID
    let name: String    // display name
}

struct AzureDatabase: Identifiable, Hashable {
    let id = UUID()
    let subscriptionId: String
    let subscriptionName: String
    let resourceGroup: String
    let serverFqdn: String
    let databaseName: String

    var displayName: String { "\(databaseName)  —  \(serverFqdn)" }
}
