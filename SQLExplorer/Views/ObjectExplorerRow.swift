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
                .font(.system(size: 12, weight: node.objectType == .connectionGroup ? .bold : .regular))
                .lineLimit(1)

            Spacer()

            if node.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.vertical, 1)
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

// Add isLoading to DatabaseObject
extension DatabaseObject {
    @MainActor var isLoading: Bool { false } // TODO: implement loading state
}
