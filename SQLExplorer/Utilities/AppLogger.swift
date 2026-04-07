import os

enum AppLogger {
    private static let subsystem = "com.sqlexplorer.app"

    static let connection = Logger(subsystem: subsystem, category: "connection")
    static let query      = Logger(subsystem: subsystem, category: "query")
    static let auth       = Logger(subsystem: subsystem, category: "auth")
    static let schema     = Logger(subsystem: subsystem, category: "schema")
}
