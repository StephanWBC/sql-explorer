import SwiftUI

struct ObjectExplorerRow: View {
    @ObservedObject var node: DatabaseObject
    var onConnect: ((DatabaseObject) -> Void)?
    var onDisconnect: ((DatabaseObject) -> Void)?
    var onNewQuery: ((DatabaseObject) -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            // Connection status dot for databases
            if node.objectType == .database {
                Circle()
                    .fill(node.isConnected ? Color.green : Color.red.opacity(0.6))
                    .frame(width: 7, height: 7)
            }

            // Server status dot (green if any child connected)
            if node.objectType == .server {
                Circle()
                    .fill(hasConnectedChild ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 7, height: 7)
            }

            // Icon
            Image(systemName: node.icon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            // Name
            Text(node.name)
                .font(.system(size: 12, weight: isGroupOrServer ? .semibold : .regular))
                .foregroundStyle(node.isConnected ? .primary : .secondary)
                .lineLimit(1)

            // Connecting spinner
            if node.isConnecting {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
            }

            Spacer()
        }
        .padding(.vertical, 1)
        .onTapGesture(count: 2) {
            if node.objectType == .database {
                if node.isConnected {
                    onNewQuery?(node)
                } else {
                    onConnect?(node)
                }
            }
        }
        .contextMenu {
            if node.objectType == .database {
                if node.isConnected {
                    Button {
                        onNewQuery?(node)
                    } label: {
                        Label("New Query", systemImage: "plus.rectangle")
                    }

                    Divider()

                    Button {
                        onDisconnect?(node)
                    } label: {
                        Label("Disconnect", systemImage: "bolt.slash")
                    }
                } else {
                    Button {
                        onConnect?(node)
                    } label: {
                        Label("Connect", systemImage: "bolt.fill")
                    }
                }
            }
        }
    }

    private var hasConnectedChild: Bool {
        node.children.contains { $0.isConnected }
    }

    private var isGroupOrServer: Bool {
        node.objectType == .connectionGroup || node.objectType == .server
    }

    private var iconColor: Color {
        switch node.objectType {
        case .server: return .blue
        case .connectionGroup: return .orange
        case .database: return node.isConnected ? .green : .purple
        case .table: return .green
        case .view: return .teal
        case .storedProcedure: return .orange
        case .function: return .pink
        case .primaryKey: return .yellow
        case .foreignKey: return .cyan
        default: return .secondary
        }
    }
}
