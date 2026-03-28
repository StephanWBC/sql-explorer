import SwiftUI

struct ResultsTableView: View {
    let result: QueryResult

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(0..<result.rows.count, id: \.self) { rowIdx in
                        HStack(spacing: 0) {
                            ForEach(0..<result.columns.count, id: \.self) { colIdx in
                                Text(result.rows[rowIdx][colIdx])
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                            }
                        }
                        .background(rowIdx % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
                    }
                } header: {
                    HStack(spacing: 0) {
                        ForEach(result.columns) { col in
                            Text(col.name)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                                .frame(width: 150, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                        }
                    }
                    .background(.bar)
                }
            }
        }
    }
}
