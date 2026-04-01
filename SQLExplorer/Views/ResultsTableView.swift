import SwiftUI
import AppKit

// MARK: - SwiftUI wrapper

struct ResultsTableView: View {
    let result: QueryResult

    private static let maxDisplayRows = 10_000

    @State private var statusText: String = ""
    @State private var showCopied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if result.rows.count > Self.maxDisplayRows {
                HStack(spacing: 4) {
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

            ResultsNSTableView(
                result: result,
                maxRows: Self.maxDisplayRows,
                statusText: $statusText,
                showCopied: $showCopied
            )

            // Status bar
            HStack(spacing: 6) {
                if showCopied {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                        Text("Copied")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(height: 22)
            .background(Color(nsColor: NSColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)))
            .animation(.easeInOut(duration: 0.2), value: showCopied)
        }
    }
}

// MARK: - Grid Coordinator (top-level for #selector visibility)

@MainActor
class DataGridCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var result: QueryResult
    var displayRowCount: Int
    weak var tableView: DataGridTableView?
    var statusText: Binding<String>
    var showCopied: Binding<Bool>

    private let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let nullFont: NSFont = {
        let desc = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            .fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: desc, size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }()
    private let rowNumBg = NSColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1)

    init(result: QueryResult, maxRows: Int, statusText: Binding<String>, showCopied: Binding<Bool>) {
        self.result = result
        self.displayRowCount = min(result.rows.count, maxRows)
        self.statusText = statusText
        self.showCopied = showCopied
    }

    // MARK: DataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayRowCount
    }

    // MARK: Delegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let identifier = tableColumn.identifier

        if identifier.rawValue == "_rowNum" {
            return makeRowNumberCell(tableView: tableView, identifier: identifier, row: row)
        } else {
            return makeDataCell(tableView: tableView, identifier: identifier, row: row)
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        24
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = tableView else { return }
        let selectedRows = tv.selectedRowIndexes

        if selectedRows.count == 1, let row = selectedRows.first {
            let clickedCol = tv.clickedColumn
            if clickedCol >= 1 {
                let colIdx = clickedCol - 1
                if colIdx < result.columns.count && row < result.rows.count {
                    let value = result.rows[row][colIdx]
                    copyToClipboard(value)
                    let colName = result.columns[colIdx].name
                    statusText.wrappedValue = "\(colName): \(value)"
                    flashCopied()
                    if let cellView = tv.view(atColumn: clickedCol, row: row, makeIfNecessary: false) {
                        flashCell(cellView)
                    }
                }
            } else {
                statusText.wrappedValue = "Row \(row + 1) selected"
            }
        } else if selectedRows.count > 1 {
            statusText.wrappedValue = "\(selectedRows.count) rows selected"
        } else {
            statusText.wrappedValue = ""
        }
    }

    // MARK: Cell builders

    private func makeRowNumberCell(tableView: NSTableView, identifier: NSUserInterfaceItemIdentifier, row: Int) -> NSView {
        let container: NSView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) {
            container = existing
            if let tf = container.subviews.first as? NSTextField {
                tf.stringValue = "\(row + 1)"
            }
        } else {
            container = NSView()
            container.identifier = identifier
            container.wantsLayer = true
            container.layer?.backgroundColor = rowNumBg.cgColor

            let tf = NSTextField(labelWithString: "\(row + 1)")
            tf.font = monoFont
            tf.textColor = .tertiaryLabelColor
            tf.alignment = .right
            tf.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                tf.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }
        return container
    }

    private func makeDataCell(tableView: NSTableView, identifier: NSUserInterfaceItemIdentifier, row: Int) -> NSView? {
        let colIdStr = identifier.rawValue.replacingOccurrences(of: "col_", with: "")
        guard let colIdx = Int(colIdStr), colIdx < result.columns.count, row < result.rows.count else {
            return nil
        }

        let value = result.rows[row][colIdx]

        let container: NSView
        let tf: NSTextField

        if let existing = tableView.makeView(withIdentifier: identifier, owner: self),
           let existingTf = existing.subviews.first as? NSTextField {
            container = existing
            tf = existingTf
        } else {
            container = NSView()
            container.identifier = identifier

            tf = NSTextField(labelWithString: "")
            tf.cell?.truncatesLastVisibleLine = true
            tf.cell?.lineBreakMode = .byTruncatingTail
            tf.isSelectable = false
            tf.drawsBackground = false
            tf.isBezeled = false
            tf.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                tf.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                tf.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }

        tf.stringValue = value

        if value == "NULL" {
            tf.font = nullFont
            tf.textColor = .tertiaryLabelColor
        } else {
            tf.font = monoFont
            tf.textColor = .labelColor
        }
        tf.alignment = .left

        return container
    }

    // MARK: Context menu actions

    @objc func copyCellAction(_ sender: Any?) {
        guard let tv = tableView else { return }
        let row = tv.contextRow
        let col = tv.contextColumn - 1
        guard row >= 0, col >= 0, col < result.columns.count, row < result.rows.count else { return }
        copyToClipboard(result.rows[row][col])
        statusText.wrappedValue = "Copied cell value"
        flashCopied()
    }

    @objc func copyRowAction(_ sender: Any?) {
        guard let tv = tableView else { return }
        let row = tv.contextRow
        guard row >= 0, row < result.rows.count else { return }
        copyToClipboard(result.rows[row].joined(separator: "\t"))
        statusText.wrappedValue = "Copied row \(row + 1)"
        flashCopied()
    }

    @objc func copyColumnAction(_ sender: Any?) {
        guard let tv = tableView else { return }
        let col = tv.contextColumn - 1
        guard col >= 0, col < result.columns.count else { return }
        let values = (0..<displayRowCount).map { result.rows[$0][col] }
        copyToClipboard(values.joined(separator: "\n"))
        statusText.wrappedValue = "Copied column \"\(result.columns[col].name)\" (\(values.count) values)"
        flashCopied()
    }

    @objc func copySelectedRowsAction(_ sender: Any?) {
        copySelected()
    }

    @objc func copyAllAction(_ sender: Any?) {
        let header = result.columns.map(\.name).joined(separator: "\t")
        let rows = (0..<displayRowCount).map { result.rows[$0].joined(separator: "\t") }
        copyToClipboard(([header] + rows).joined(separator: "\n"))
        statusText.wrappedValue = "Copied all \(displayRowCount) rows with headers"
        flashCopied()
    }

    @objc func copyAsCSVAction(_ sender: Any?) {
        let header = result.columns.map { csvEscape($0.name) }.joined(separator: ",")
        let rows = (0..<displayRowCount).map { rowIdx in
            result.rows[rowIdx].map { csvEscape($0) }.joined(separator: ",")
        }
        copyToClipboard(([header] + rows).joined(separator: "\n"))
        statusText.wrappedValue = "Copied as CSV (\(displayRowCount) rows)"
        flashCopied()
    }

    @objc func copyAsInsertAction(_ sender: Any?) {
        guard let tv = tableView else { return }
        let selectedRows = tv.selectedRowIndexes
        let rowIndices = selectedRows.isEmpty ? IndexSet(0..<displayRowCount) : selectedRows

        let colNames = result.columns.map(\.name).joined(separator: ", ")
        var statements: [String] = []

        for rowIdx in rowIndices {
            guard rowIdx < result.rows.count else { continue }
            let values = result.rows[rowIdx].map { val -> String in
                if val == "NULL" { return "NULL" }
                return "'\(val.replacingOccurrences(of: "'", with: "''"))'"
            }
            statements.append("INSERT INTO [TableName] (\(colNames)) VALUES (\(values.joined(separator: ", ")));")
        }

        copyToClipboard(statements.joined(separator: "\n"))
        statusText.wrappedValue = "Copied \(statements.count) INSERT statement(s)"
        flashCopied()
    }

    // MARK: Keyboard copy

    func copySelected() {
        guard let tv = tableView else { return }
        let selectedRows = tv.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        let rows = selectedRows.map { result.rows[$0].joined(separator: "\t") }
        copyToClipboard(rows.joined(separator: "\n"))
        statusText.wrappedValue = "Copied \(selectedRows.count) row(s)"
        flashCopied()
    }

    func copySelectedWithHeaders() {
        guard let tv = tableView else { return }
        let selectedRows = tv.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        let header = result.columns.map(\.name).joined(separator: "\t")
        let rows = selectedRows.map { result.rows[$0].joined(separator: "\t") }
        copyToClipboard(([header] + rows).joined(separator: "\n"))
        statusText.wrappedValue = "Copied \(selectedRows.count) row(s) with headers"
        flashCopied()
    }

    // MARK: Helpers

    private func copyToClipboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func flashCopied() {
        showCopied.wrappedValue = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.showCopied.wrappedValue = false
        }
    }

    private func flashCell(_ cellView: NSView) {
        let flash = NSView(frame: cellView.bounds)
        flash.wantsLayer = true
        flash.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        flash.layer?.cornerRadius = 2
        flash.alphaValue = 1
        flash.autoresizingMask = [.width, .height]
        cellView.addSubview(flash)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            flash.animator().alphaValue = 0
        } completionHandler: {
            flash.removeFromSuperview()
        }
    }
}

// MARK: - Custom NSTableView subclass with copy & context menu

class DataGridTableView: NSTableView {
    weak var gridCoordinator: DataGridCoordinator?

    var contextColumn: Int = -1
    var contextRow: Int = -1

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        contextRow = row(at: point)
        contextColumn = column(at: point)

        guard contextRow >= 0, let coordinator = gridCoordinator else { return nil }

        let menu = NSMenu()

        if contextColumn >= 1 {
            let cellItem = NSMenuItem(title: "Copy Cell Value", action: #selector(DataGridCoordinator.copyCellAction(_:)), keyEquivalent: "")
            cellItem.target = coordinator
            cellItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            menu.addItem(cellItem)
        }

        let rowItem = NSMenuItem(title: "Copy Row", action: #selector(DataGridCoordinator.copyRowAction(_:)), keyEquivalent: "")
        rowItem.target = coordinator
        rowItem.image = NSImage(systemSymbolName: "arrow.right.doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(rowItem)

        if contextColumn >= 1 {
            let colItem = NSMenuItem(title: "Copy Column", action: #selector(DataGridCoordinator.copyColumnAction(_:)), keyEquivalent: "")
            colItem.target = coordinator
            colItem.image = NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: nil)
            menu.addItem(colItem)
        }

        menu.addItem(.separator())

        if selectedRowIndexes.count > 1 {
            let selItem = NSMenuItem(title: "Copy Selected Rows (\(selectedRowIndexes.count))", action: #selector(DataGridCoordinator.copySelectedRowsAction(_:)), keyEquivalent: "")
            selItem.target = coordinator
            menu.addItem(selItem)
        }

        let allItem = NSMenuItem(title: "Copy All with Headers", action: #selector(DataGridCoordinator.copyAllAction(_:)), keyEquivalent: "")
        allItem.target = coordinator
        menu.addItem(allItem)

        menu.addItem(.separator())

        let csvItem = NSMenuItem(title: "Copy as CSV", action: #selector(DataGridCoordinator.copyAsCSVAction(_:)), keyEquivalent: "")
        csvItem.target = coordinator
        csvItem.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)
        menu.addItem(csvItem)

        let insertItem = NSMenuItem(title: "Copy as INSERT Statements", action: #selector(DataGridCoordinator.copyAsInsertAction(_:)), keyEquivalent: "")
        insertItem.target = coordinator
        insertItem.image = NSImage(systemSymbolName: "plus.square", accessibilityDescription: nil)
        menu.addItem(insertItem)

        return menu
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            if event.modifierFlags.contains(.shift) {
                gridCoordinator?.copySelectedWithHeaders()
            } else {
                gridCoordinator?.copySelected()
            }
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - NSViewRepresentable

struct ResultsNSTableView: NSViewRepresentable {
    let result: QueryResult
    let maxRows: Int
    @Binding var statusText: String
    @Binding var showCopied: Bool

    typealias Coordinator = DataGridCoordinator

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = DataGridTableView()
        tableView.gridCoordinator = context.coordinator
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.gridColor = NSColor.separatorColor.withAlphaComponent(0.15)
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true

        let headerView = NSTableHeaderView()
        tableView.headerView = headerView

        buildColumns(tableView: tableView, result: result)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        context.coordinator.tableView = tableView

        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? DataGridTableView else { return }

        let coordinator = context.coordinator
        let newResult = result

        if coordinator.result.columns.count != newResult.columns.count ||
            coordinator.result.rows.count != newResult.rows.count {

            coordinator.result = newResult
            coordinator.displayRowCount = min(newResult.rows.count, maxRows)
            tableView.gridCoordinator = coordinator

            while tableView.tableColumns.count > 0 {
                tableView.removeTableColumn(tableView.tableColumns[0])
            }

            buildColumns(tableView: tableView, result: newResult)
            tableView.reloadData()
        }
    }

    private func buildColumns(tableView: NSTableView, result: QueryResult) {
        let displayRows = min(result.rows.count, maxRows)
        let sampleCount = min(displayRows, 100)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: monoFont]

        let rowNumCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("_rowNum"))
        rowNumCol.title = "#"
        rowNumCol.width = 50
        rowNumCol.minWidth = 40
        rowNumCol.maxWidth = 80
        rowNumCol.headerCell.alignment = .right
        tableView.addTableColumn(rowNumCol)

        for col in result.columns {
            let nsCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_\(col.id)"))
            nsCol.title = col.name
            nsCol.minWidth = 60
            nsCol.maxWidth = 800
            nsCol.headerToolTip = "\(col.name) (\(col.dataType))"

            let headerSize = (col.name as NSString).size(withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
            ])
            var maxWidth = headerSize.width + 28

            for rowIdx in 0..<sampleCount {
                let value = result.rows[rowIdx][col.id]
                let size = (value as NSString).size(withAttributes: attrs)
                maxWidth = max(maxWidth, size.width + 24)
            }

            nsCol.width = min(max(maxWidth, 60), 500)
            tableView.addTableColumn(nsCol)
        }
    }

    func makeCoordinator() -> DataGridCoordinator {
        DataGridCoordinator(result: result, maxRows: maxRows, statusText: $statusText, showCopied: $showCopied)
    }
}
