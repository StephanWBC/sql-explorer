import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            // Connection dot
            Circle()
                .fill(appState.connectionManager.isConnected ? Color.green : Color.gray)
                .frame(width: 7, height: 7)

            Text(appState.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if appState.connectionManager.isConnected {
                Text("DB: \(appState.currentDatabase)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("\(appState.connectionManager.activeConnectionIds.count) connection(s)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
