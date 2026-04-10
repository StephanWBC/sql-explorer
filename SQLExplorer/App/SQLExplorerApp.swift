import SwiftUI

@main
struct SQLExplorerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1400, height: 900)

        Window("Database Diagram", id: "erd") {
            ERDWindowView()
                .environmentObject(appState)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Query Tab") {
                    newQueryTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save Diagram") {
                    if let schema = appState.erdSchema, !schema.tables.isEmpty {
                        if schema.savedDiagramId != nil {
                            appState.saveDiagram(name: schema.savedDiagramName)
                        } else {
                            appState.saveDiagram(name: schema.databaseName + " Diagram")
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appState.erdSchema?.tables.isEmpty ?? true)

                Divider()

                Button("Close Tab") {
                    appState.closeCurrentTab()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("Query") {
                Button("Execute") {
                    Task { await executeCurrentQuery() }
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func newQueryTab() {
        guard let connId = appState.activeConnectionId else { return }
        let tab = QueryTab(
            title: "\(appState.currentDatabase) — Query \(appState.queryTabs.count + 1)",
            connectionId: connId,
            database: appState.currentDatabase
        )
        appState.queryTabs.append(tab)
        appState.selectedTabId = tab.id
    }

    @MainActor
    private func executeCurrentQuery() async {
        guard let tabId = appState.selectedTabId,
              let tabIdx = appState.queryTabs.firstIndex(where: { $0.id == tabId }),
              !appState.queryTabs[tabIdx].sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        appState.queryTabs[tabIdx].isExecuting = true
        appState.statusMessage = "Executing..."

        do {
            let result = try await appState.connectionManager.executeQuery(
                appState.queryTabs[tabIdx].sql,
                connectionId: appState.queryTabs[tabIdx].connectionId)
            appState.queryTabs[tabIdx].result = result
            appState.statusMessage = "\(result.rows.count) row(s) in \(result.elapsedMs)ms"
        } catch {
            appState.queryTabs[tabIdx].result = QueryResult(errorMessage: error.localizedDescription)
            appState.statusMessage = "Error: \(error.localizedDescription)"
        }

        appState.queryTabs[tabIdx].isExecuting = false
    }
}
