import SwiftUI

struct ERDWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let schema = appState.erdSchema {
                if schema.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading database diagram...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = schema.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.red)
                        Text("Failed to load diagram")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // Toolbar
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.connected.to.line.below")
                                .foregroundStyle(.blue)
                            Text(schema.databaseName)
                                .font(.system(size: 13, weight: .semibold))

                            Spacer()

                            Text("\(schema.tables.count) tables")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)

                            if !schema.relationships.isEmpty {
                                Text("\(schema.relationships.count) relationships")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                resetLayout()
                            } label: {
                                Label("Reset Layout", systemImage: "arrow.counterclockwise")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary)
                            .cornerRadius(4)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.bar)

                        Divider()

                        if schema.tables.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tablecells")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.quaternary)
                                Text("No tables found")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ERDCanvasRepresentable(schema: schema)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.connected.to.line.below")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("Open a Database Diagram from the context menu")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func resetLayout() {
        guard let schema = appState.erdSchema else { return }
        let cols = max(Int(ceil(sqrt(Double(schema.tables.count)))), 1)
        let spacing: CGFloat = 40
        let tableWidth: CGFloat = 240

        for (index, table) in schema.tables.enumerated() {
            let gridCol = index % cols
            let gridRow = index / cols
            table.position = CGPoint(
                x: CGFloat(gridCol) * (tableWidth + spacing) + 40,
                y: CGFloat(gridRow) * (200 + spacing) + 40
            )
        }
        schema.objectWillChange.send()
    }
}
