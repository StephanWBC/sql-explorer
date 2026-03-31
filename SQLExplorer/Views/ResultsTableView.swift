import SwiftUI
import AppKit

// MARK: - SwiftUI wrapper

struct ResultsTableView: View {
    let result: QueryResult

    private static let maxDisplayRows = 10_000

    var body: some View {
        VStack(spacing: 0) {
            if result.rows.count > Self.maxDisplayRows {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)
                    Text("Showing first \(Self.maxDisplayRows.formatted()) of \(result.rows.count.formatted()) rows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.bar)
            }

            ResultsNSTableView(result: result, maxRows: Self.maxDisplayRows)
        }
    }
}

// MARK: - NSTableView wrapper

struct ResultsNSTableView: NSViewRepresentable {
    let result: QueryResult
    let maxRows: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.gridColor = NSColor.separatorColor.withAlphaComponent(0.3)
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)

        // Header
        let headerView = NSTableHeaderView()
        tableView.headerView = headerView

        // Row number column
        let rowNumCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("_rowNum"))
        rowNumCol.title = "#"
        rowNumCol.width = 50
        rowNumCol.minWidth = 40
        rowNumCol.maxWidth = 80
        rowNumCol.headerCell.alignment = .right
        tableView.addTableColumn(rowNumCol)

        // Data columns — measure widths from content
        let displayRows = min(result.rows.count, maxRows)
        let sampleCount = min(displayRows, 100)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: monoFont]

        for col in result.columns {
            let nsCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_\(col.id)"))
            nsCol.title = col.name
            nsCol.minWidth = 60
            nsCol.maxWidth = 600

            // Measure header width
            let headerSize = (col.name as NSString).size(withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
            ])
            var maxWidth = headerSize.width + 24

            // Measure content width from sample rows
            for rowIdx in 0..<sampleCount {
                let value = result.rows[rowIdx][col.id]
                let size = (value as NSString).size(withAttributes: attrs)
                maxWidth = max(maxWidth, size.width + 20)
            }

            nsCol.width = min(max(maxWidth, 60), 400)
            tableView.addTableColumn(nsCol)
        }

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }

        let coordinator = context.coordinator
        let newResult = result

        // Only rebuild if result changed
        if coordinator.result.columns.count != newResult.columns.count ||
            coordinator.result.rows.count != newResult.rows.count {

            coordinator.result = newResult
            coordinator.displayRowCount = min(newResult.rows.count, maxRows)

            // Remove old columns and rebuild
            while tableView.tableColumns.count > 0 {
                tableView.removeTableColumn(tableView.tableColumns[0])
            }

            // Row number column
            let rowNumCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("_rowNum"))
            rowNumCol.title = "#"
            rowNumCol.width = 50
            rowNumCol.minWidth = 40
            rowNumCol.maxWidth = 80
            rowNumCol.headerCell.alignment = .right
            tableView.addTableColumn(rowNumCol)

            // Data columns
            let sampleCount = min(coordinator.displayRowCount, 100)
            let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [.font: monoFont]

            for col in newResult.columns {
                let nsCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_\(col.id)"))
                nsCol.title = col.name
                nsCol.minWidth = 60
                nsCol.maxWidth = 600

                let headerSize = (col.name as NSString).size(withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
                ])
                var maxWidth = headerSize.width + 24

                for rowIdx in 0..<sampleCount {
                    let value = newResult.rows[rowIdx][col.id]
                    let size = (value as NSString).size(withAttributes: attrs)
                    maxWidth = max(maxWidth, size.width + 20)
                }

                nsCol.width = min(max(maxWidth, 60), 400)
                tableView.addTableColumn(nsCol)
            }

            tableView.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(result: result, maxRows: maxRows)
    }

    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var result: QueryResult
        var displayRowCount: Int

        private let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        private let headerFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        private let nullFont: NSFont = {
            let desc = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                .fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: desc, size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        }()

        init(result: QueryResult, maxRows: Int) {
            self.result = result
            self.displayRowCount = min(result.rows.count, maxRows)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            displayRowCount
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            let identifier = tableColumn.identifier

            let cellView: NSTextField
            if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
                cellView = existing
            } else {
                cellView = NSTextField(labelWithString: "")
                cellView.identifier = identifier
                cellView.cell?.truncatesLastVisibleLine = true
                cellView.cell?.lineBreakMode = .byTruncatingTail
                cellView.isSelectable = true
            }

            if identifier.rawValue == "_rowNum" {
                // Row number
                cellView.stringValue = "\(row + 1)"
                cellView.font = monoFont
                cellView.textColor = .secondaryLabelColor
                cellView.alignment = .right
            } else {
                // Data cell
                let colIdStr = identifier.rawValue.replacingOccurrences(of: "col_", with: "")
                guard let colIdx = Int(colIdStr), colIdx < result.columns.count, row < result.rows.count else {
                    cellView.stringValue = ""
                    return cellView
                }

                let value = result.rows[row][colIdx]
                cellView.stringValue = value

                if value == "NULL" {
                    cellView.font = nullFont
                    cellView.textColor = .tertiaryLabelColor
                } else {
                    cellView.font = monoFont
                    cellView.textColor = .labelColor
                }
                cellView.alignment = .left
            }

            return cellView
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            22
        }
    }
}
