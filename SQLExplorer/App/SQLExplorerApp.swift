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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection") {
                    // TODO: open connection sheet
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Query Tab") {
                    newQueryTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandMenu("Query") {
                Button("Execute") {
                    // TODO: execute current query
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func newQueryTab() {
        guard let connId = appState.activeConnectionId else { return }
        let tab = QueryTab(
            title: "Query \(appState.queryTabs.count + 1)",
            connectionId: connId,
            database: appState.currentDatabase
        )
        appState.queryTabs.append(tab)
        appState.selectedTabId = tab.id
    }
}
