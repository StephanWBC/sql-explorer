import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

// MARK: - Cell coordinate for selection tracking

struct CellCoord: Hashable {
    let row: Int
    let col: Int  // data column index (0-based, excludes row number column)
}

// MARK: - Grid Coordinator

@MainActor
class DataGridCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var result: QueryResult
    var displayRowCount: Int
    weak var tableView: DataGridTableView?
    var statusText: Binding<String>
    var showCopied: Binding<Bool>

    // Cell-level selection
    var selectedCells: Set<CellCoord> = []
    var selectedWholeRows: Set<Int> = []  // rows selected by clicking row number

    private let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let nullFont: NSFont = {
        let desc = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            .fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: desc, size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }()
    private let rowNumBg = NSColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1)
    private let cellHighlight = NSColor.controlAccentColor.withAlphaComponent(0.25)
    private let rowHighlight = NSColor.controlAccentColor.withAlphaComponent(0.15)

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

    // We disable NSTableView's built-in selection — we manage our own
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }

    // MARK: Cell selection handling (called from DataGridTableView.mouseDown)

    func handleCellClick(row: Int, tableColumn: Int, shift: Bool) {
        guard let tv = tableView else { return }
        let dataCol = tableColumn - 1  // offset for row number column

        if tableColumn == 0 {
            // Clicked row number → select entire row
            if shift && !selectedWholeRows.isEmpty {
                let anchor = selectedWholeRows.min() ?? row
                let range = min(anchor, row)...max(anchor, row)
                selectedWholeRows = Set(range)
                selectedCells.removeAll()
            } else if shift {
                selectedWholeRows.insert(row)
            } else {
                selectedCells.removeAll()
                selectedWholeRows = [row]
            }
            updateStatus()
        } else if dataCol >= 0 && dataCol < result.columns.count && row < result.rows.count {
            // Clicked a data cell
            let coord = CellCoord(row: row, col: dataCol)
            if shift {
                // Shift-click: extend selection range
                selectedWholeRows.removeAll()
                if let anchor = selectedCells.first {
                    let minRow = min(anchor.row, row)
                    let maxRow = max(anchor.row, row)
                    let minCol = min(anchor.col, dataCol)
                    let maxCol = max(anchor.col, dataCol)
                    selectedCells.removeAll()
                    for r in minRow...maxRow {
                        for c in minCol...maxCol {
                            selectedCells.insert(CellCoord(row: r, col: c))
                        }
                    }
                } else {
                    selectedCells = [coord]
                }
            } else {
                selectedWholeRows.removeAll()
                selectedCells = [coord]
            }
            updateStatus()
        }

        tv.needsDisplay = true
        // Redraw visible cells to update highlights
        let visibleRows = tv.rows(in: tv.visibleRect)
        tv.reloadData(forRowIndexes: IndexSet(integersIn: visibleRows.location..<(visibleRows.location + visibleRows.length)),
                      columnIndexes: IndexSet(integersIn: 0..<tv.numberOfColumns))
    }

    private func updateStatus() {
        if !selectedWholeRows.isEmpty {
            if selectedWholeRows.count == 1 {
                statusText.wrappedValue = "Row \(selectedWholeRows.first! + 1) selected"
            } else {
                statusText.wrappedValue = "\(selectedWholeRows.count) rows selected"
            }
        } else if selectedCells.count == 1, let cell = selectedCells.first {
            let colName = result.columns[cell.col].name
            let value = result.rows[cell.row][cell.col]
            statusText.wrappedValue = "\(colName): \(value)"
        } else if selectedCells.count > 1 {
            let rows = Set(selectedCells.map(\.row)).count
            let cols = Set(selectedCells.map(\.col)).count
            statusText.wrappedValue = "\(selectedCells.count) cells selected (\(rows) rows × \(cols) cols)"
        } else {
            statusText.wrappedValue = ""
        }
    }

    func isCellSelected(row: Int, dataCol: Int) -> Bool {
        selectedWholeRows.contains(row) || selectedCells.contains(CellCoord(row: row, col: dataCol))
    }

    func isRowSelected(_ row: Int) -> Bool {
        selectedWholeRows.contains(row)
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

        // Highlight row number if whole row selected
        container.wantsLayer = true
        container.layer?.backgroundColor = isRowSelected(row)
            ? NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
            : rowNumBg.cgColor

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
            container.wantsLayer = true

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

        // Cell highlight
        container.wantsLayer = true
        if isCellSelected(row: row, dataCol: colIdx) {
            container.layer?.backgroundColor = cellHighlight.cgColor
        } else if isRowSelected(row) {
            container.layer?.backgroundColor = rowHighlight.cgColor
        } else {
            container.layer?.backgroundColor = nil
        }

        return container
    }

    // MARK: Copy logic

    func copyCurrentSelection() {
        if !selectedWholeRows.isEmpty {
            let sortedRows = selectedWholeRows.sorted()
            let text = sortedRows.map { result.rows[$0].joined(separator: "\t") }.joined(separator: "\n")
            copyToClipboard(text)
            statusText.wrappedValue = "Copied \(sortedRows.count) row(s)"
            flashCopied()
        } else if !selectedCells.isEmpty {
            let sortedCells = selectedCells.sorted { $0.row == $1.row ? $0.col < $1.col : $0.row < $1.row }
            let minRow = sortedCells.first!.row, maxRow = sortedCells.last!.row
            let minCol = sortedCells.map(\.col).min()!, maxCol = sortedCells.map(\.col).max()!

            var lines: [String] = []
            for r in minRow...maxRow {
                var cells: [String] = []
                for c in minCol...maxCol {
                    if selectedCells.contains(CellCoord(row: r, col: c)) {
                        cells.append(result.rows[r][c])
                    } else {
                        cells.append("")
                    }
                }
                lines.append(cells.joined(separator: "\t"))
            }
            copyToClipboard(lines.joined(separator: "\n"))
            if selectedCells.count == 1, let cell = selectedCells.first {
                statusText.wrappedValue = "Copied: \(result.rows[cell.row][cell.col])"
            } else {
                statusText.wrappedValue = "Copied \(selectedCells.count) cells"
            }
            flashCopied()
        }
    }

    func copyCurrentSelectionWithHeaders() {
        if !selectedWholeRows.isEmpty {
            let header = result.columns.map(\.name).joined(separator: "\t")
            let sortedRows = selectedWholeRows.sorted()
            let text = sortedRows.map { result.rows[$0].joined(separator: "\t") }.joined(separator: "\n")
            copyToClipboard(header + "\n" + text)
            statusText.wrappedValue = "Copied \(sortedRows.count) row(s) with headers"
            flashCopied()
        } else if !selectedCells.isEmpty {
            let minCol = selectedCells.map(\.col).min()!
            let maxCol = selectedCells.map(\.col).max()!
            let header = (minCol...maxCol).map { result.columns[$0].name }.joined(separator: "\t")
            copyCurrentSelection() // copies cells
            // prepend header
            let pb = NSPasteboard.general
            if let existing = pb.string(forType: .string) {
                pb.clearContents()
                pb.setString(header + "\n" + existing, forType: .string)
            }
            statusText.wrappedValue = "Copied \(selectedCells.count) cells with headers"
            flashCopied()
        }
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

    @objc func copySelectedAction(_ sender: Any?) {
        copyCurrentSelection()
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
        let rowIndices: [Int]
        if !selectedWholeRows.isEmpty {
            rowIndices = selectedWholeRows.sorted()
        } else {
            rowIndices = Array(0..<displayRowCount)
        }

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

    @objc func copyAsJSONAction(_ sender: Any?) {
        let rowIndices: [Int]
        if !selectedWholeRows.isEmpty {
            rowIndices = selectedWholeRows.sorted()
        } else {
            rowIndices = Array(0..<displayRowCount)
        }

        var jsonRows: [[String: Any]] = []
        for rowIdx in rowIndices {
            guard rowIdx < result.rows.count else { continue }
            var dict: [String: Any] = [:]
            for (colIdx, col) in result.columns.enumerated() {
                let val = result.rows[rowIdx][colIdx]
                dict[col.name] = val == "NULL" ? NSNull() : val
            }
            jsonRows.append(dict)
        }

        if let data = try? JSONSerialization.data(withJSONObject: jsonRows, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            copyToClipboard(jsonString)
            statusText.wrappedValue = "Copied as JSON (\(rowIndices.count) rows)"
            flashCopied()
        }
    }

    @objc func exportAsCSVAction(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.title = "Export as CSV"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "export.csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let header = result.columns.map { csvEscape($0.name) }.joined(separator: ",")
        let rows = (0..<displayRowCount).map { rowIdx in
            result.rows[rowIdx].map { csvEscape($0) }.joined(separator: ",")
        }
        let content = ([header] + rows).joined(separator: "\n")

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            statusText.wrappedValue = "Exported \(displayRowCount) rows to \(url.lastPathComponent)"
            flashCopied()
        } catch {
            statusText.wrappedValue = "Export failed: \(error.localizedDescription)"
        }
    }

    @objc func exportAsJSONAction(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.title = "Export as JSON"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "export.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var jsonRows: [[String: Any]] = []
        for rowIdx in 0..<displayRowCount {
            guard rowIdx < result.rows.count else { continue }
            var dict: [String: Any] = [:]
            for (colIdx, col) in result.columns.enumerated() {
                let val = result.rows[rowIdx][colIdx]
                dict[col.name] = val == "NULL" ? NSNull() : val
            }
            jsonRows.append(dict)
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: jsonRows, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            statusText.wrappedValue = "Exported \(displayRowCount) rows to \(url.lastPathComponent)"
            flashCopied()
        } catch {
            statusText.wrappedValue = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: Helpers

    func copyToClipboard(_ string: String) {
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

    func flashCopied() {
        showCopied.wrappedValue = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.showCopied.wrappedValue = false
        }
    }
}

// MARK: - Custom NSTableView with cell-level selection

class DataGridTableView: NSTableView {
    weak var gridCoordinator: DataGridCoordinator?

    var contextColumn: Int = -1
    var contextRow: Int = -1

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        let clickedCol = column(at: point)
        let shift = event.modifierFlags.contains(.shift)

        guard clickedRow >= 0 else {
            gridCoordinator?.selectedCells.removeAll()
            gridCoordinator?.selectedWholeRows.removeAll()
            return
        }

        gridCoordinator?.handleCellClick(row: clickedRow, tableColumn: clickedCol, shift: shift)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        contextRow = row(at: point)
        contextColumn = column(at: point)

        guard contextRow >= 0, let coordinator = gridCoordinator else { return nil }

        let menu = NSMenu()

        // Copy Cell
        if contextColumn >= 1 {
            let cellItem = NSMenuItem(title: "Copy Cell Value", action: #selector(DataGridCoordinator.copyCellAction(_:)), keyEquivalent: "")
            cellItem.target = coordinator
            cellItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            menu.addItem(cellItem)
        }

        // Copy Row
        let rowItem = NSMenuItem(title: "Copy Row", action: #selector(DataGridCoordinator.copyRowAction(_:)), keyEquivalent: "")
        rowItem.target = coordinator
        rowItem.image = NSImage(systemSymbolName: "arrow.right.doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(rowItem)

        // Copy Column
        if contextColumn >= 1 {
            let colItem = NSMenuItem(title: "Copy Column", action: #selector(DataGridCoordinator.copyColumnAction(_:)), keyEquivalent: "")
            colItem.target = coordinator
            colItem.image = NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: nil)
            menu.addItem(colItem)
        }

        menu.addItem(.separator())

        // Copy Selection (if multi-cell or multi-row)
        let selCount = coordinator.selectedCells.count + coordinator.selectedWholeRows.count
        if selCount > 1 {
            let selItem = NSMenuItem(title: "Copy Selection", action: #selector(DataGridCoordinator.copySelectedAction(_:)), keyEquivalent: "")
            selItem.target = coordinator
            menu.addItem(selItem)
        }

        // Copy All
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

        let jsonItem = NSMenuItem(title: "Copy as JSON", action: #selector(DataGridCoordinator.copyAsJSONAction(_:)), keyEquivalent: "")
        jsonItem.target = coordinator
        jsonItem.image = NSImage(systemSymbolName: "curlybraces", accessibilityDescription: nil)
        menu.addItem(jsonItem)

        menu.addItem(.separator())

        let exportCSVItem = NSMenuItem(title: "Export to CSV File...", action: #selector(DataGridCoordinator.exportAsCSVAction(_:)), keyEquivalent: "")
        exportCSVItem.target = coordinator
        exportCSVItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        menu.addItem(exportCSVItem)

        let exportJSONItem = NSMenuItem(title: "Export to JSON File...", action: #selector(DataGridCoordinator.exportAsJSONAction(_:)), keyEquivalent: "")
        exportJSONItem.target = coordinator
        exportJSONItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        menu.addItem(exportJSONItem)

        return menu
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            if event.modifierFlags.contains(.shift) {
                gridCoordinator?.copyCurrentSelectionWithHeaders()
            } else {
                gridCoordinator?.copyCurrentSelection()
            }
            return
        }
        super.keyDown(with: event)
    }

    // Disable built-in row highlight drawing — we draw our own cell highlights
    override func highlightSelection(inClipRect clipRect: NSRect) {
        // intentionally empty
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
        tableView.allowsMultipleSelection = false
        tableView.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        tableView.selectionHighlightStyle = .none  // we draw our own
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
            coordinator.selectedCells.removeAll()
            coordinator.selectedWholeRows.removeAll()
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
