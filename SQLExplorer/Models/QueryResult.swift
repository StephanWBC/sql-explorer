import Foundation

struct QueryResultColumn: Identifiable {
    let id: Int
    let name: String
    let dataType: String
}

struct QueryResult {
    var columns: [QueryResultColumn] = []
    var rows: [[String]] = []         // All values as strings for display
    var rowsAffected: Int = 0
    var elapsedMs: Int64 = 0
    var messages: [String] = []
    var errorMessage: String?

    var isError: Bool { errorMessage != nil }
    var hasResults: Bool { !columns.isEmpty }
}
