import SwiftUI

struct ObjectExplorerRow: View {
    @ObservedObject var node: DatabaseObject

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.icon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            Text(node.name)
                .font(.system(size: 12, weight: isGroupOrServer ? .semibold : .regular))
                .lineLimit(1)

            // Environment badge
            if let env = node.environmentLabel, !env.isEmpty {
                Text(env)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(EnvironmentLabel.from(env)?.color ?? .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(EnvironmentLabel.from(env)?.badgeBackground ?? Color.clear)
                    .clipShape(Capsule())
            }

            // Child count for groups
            if node.objectType == .connectionGroup {
                Text("(\(node.children.count))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 1)
    }

    private var isGroupOrServer: Bool {
        node.objectType == .connectionGroup || node.objectType == .server
    }

    private var iconColor: Color {
        switch node.objectType {
        case .server: return .blue
        case .connectionGroup: return .orange
        case .database: return .purple
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
