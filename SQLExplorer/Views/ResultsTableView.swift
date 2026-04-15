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

                // Selection tips (subtle)
                Text("⌘C copy · ⌘⇧C +headers · ⌘A all · drag to box-select")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
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

    // Cell-level selection (stored in data-column indices)
    var selectedCells: Set<CellCoord> = []
    var selectedWholeRows: Set<Int> = []
    var selectedWholeColumns: Set<Int> = []  // data column indices

    // Anchors for range extension (shift+click, drag, shift+arrow)
    var cellAnchor: CellCoord?
    var rowAnchor: Int?
    var columnAnchor: Int?

    // Cursor for keyboard nav (current focused cell)
    var cursor: CellCoord?

    private let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let nullFont: NSFont = {
        let desc = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            .fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: desc, size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }()
    private let rowNumBg = NSColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1)
    private let cellHighlight = NSColor.controlAccentColor.withAlphaComponent(0.25)
    private let rowHighlight = NSColor.controlAccentColor.withAlphaComponent(0.15)
    private let cursorRing = NSColor.controlAccentColor.withAlphaComponent(0.85)

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

    // MARK: Visual column <-> data column mapping (handles column reordering)

    func dataColumn(forVisualColumn visualCol: Int) -> Int {
        guard let tv = tableView, visualCol >= 0, visualCol < tv.tableColumns.count else { return -1 }
        let id = tv.tableColumns[visualCol].identifier.rawValue
        if id == "_rowNum" { return -1 }
        return Int(id.replacingOccurrences(of: "col_", with: "")) ?? -1
    }

    func visualColumn(forDataColumn dataCol: Int) -> Int {
        guard let tv = tableView else { return -1 }
        let id = "col_\(dataCol)"
        for (idx, col) in tv.tableColumns.enumerated() where col.identifier.rawValue == id {
            return idx
        }
        return -1
    }

    // MARK: Cell click handling

    func handleCellClick(visualRow: Int, visualCol: Int, shift: Bool, cmd: Bool) {
        guard let tv = tableView else { return }

        // Row number column clicked → whole row
        if visualCol == 0 {
            if cmd {
                if selectedWholeRows.contains(visualRow) {
                    selectedWholeRows.remove(visualRow)
                } else {
                    selectedWholeRows.insert(visualRow)
                }
                rowAnchor = visualRow
            } else if shift, let anchor = rowAnchor {
                selectedCells.removeAll()
                selectedWholeColumns.removeAll()
                selectedWholeRows = Set(min(anchor, visualRow)...max(anchor, visualRow))
            } else {
                selectedCells.removeAll()
                selectedWholeColumns.removeAll()
                selectedWholeRows = [visualRow]
                rowAnchor = visualRow
            }
            cursor = nil
            updateStatus()
            redrawVisible()
            return
        }

        // Data cell clicked
        let dataCol = dataColumn(forVisualColumn: visualCol)
        guard dataCol >= 0, dataCol < result.columns.count, visualRow < result.rows.count else { return }

        let coord = CellCoord(row: visualRow, col: dataCol)

        if cmd {
            // Toggle single cell, keep other selection
            if selectedCells.contains(coord) {
                selectedCells.remove(coord)
            } else {
                selectedCells.insert(coord)
            }
            cellAnchor = coord
            cursor = coord
        } else if shift, let anchor = cellAnchor ?? cursor {
            // Rectangular extend
            selectedWholeRows.removeAll()
            selectedWholeColumns.removeAll()
            selectedCells = rectangle(from: anchor, to: coord)
            cursor = coord
        } else {
            // Plain click
            selectedWholeRows.removeAll()
            selectedWholeColumns.removeAll()
            selectedCells = [coord]
            cellAnchor = coord
            cursor = coord
        }

        updateStatus()
        redrawVisible()
        _ = tv  // silence warning
    }

    // MARK: Drag selection

    func handleDragSelection(startVisualRow: Int, startVisualCol: Int, endVisualRow: Int, endVisualCol: Int) {
        guard let tv = tableView else { return }
        let minR = max(0, min(startVisualRow, endVisualRow))
        let maxR = min(displayRowCount - 1, max(startVisualRow, endVisualRow))

        // Drag that started in the row-number column → whole-row selection
        if startVisualCol == 0 {
            selectedCells.removeAll()
            selectedWholeColumns.removeAll()
            selectedWholeRows = minR <= maxR ? Set(minR...maxR) : []
            rowAnchor = startVisualRow
        } else {
            // Rectangular data-cell selection, clamped to valid data columns
            let startDC = dataColumn(forVisualColumn: startVisualCol)
            var endDC = dataColumn(forVisualColumn: endVisualCol)
            if endDC < 0 {
                // Dragged into row-number column — clamp to first data column
                endDC = dataColumn(forVisualColumn: 1)
            }
            guard startDC >= 0, endDC >= 0 else { return }

            let minVCol = min(startVisualCol, endVisualCol)
            let maxVCol = max(startVisualCol, endVisualCol)
            let dataCols: [Int] = stride(from: max(1, minVCol), through: max(1, maxVCol), by: 1).compactMap { v in
                let dc = dataColumn(forVisualColumn: v)
                return dc >= 0 ? dc : nil
            }

            selectedWholeRows.removeAll()
            selectedWholeColumns.removeAll()
            selectedCells.removeAll()
            if minR <= maxR {
                for r in minR...maxR {
                    for c in dataCols {
                        selectedCells.insert(CellCoord(row: r, col: c))
                    }
                }
            }
            cellAnchor = CellCoord(row: startVisualRow, col: startDC)
            cursor = CellCoord(row: endVisualRow, col: endDC)
        }

        updateStatus()
        redrawVisible()
        _ = tv
    }

    // MARK: Column header click

    func handleColumnHeaderClick(visualCol: Int, shift: Bool, cmd: Bool) {
        // Row-number column header → select everything
        if visualCol == 0 {
            selectAll()
            return
        }
        let dataCol = dataColumn(forVisualColumn: visualCol)
        guard dataCol >= 0 else { return }

        if cmd {
            if selectedWholeColumns.contains(dataCol) {
                selectedWholeColumns.remove(dataCol)
            } else {
                selectedWholeColumns.insert(dataCol)
            }
            columnAnchor = dataCol
        } else if shift, let anchor = columnAnchor {
            // Extend column range via visual order (so reordered columns select contiguously as seen)
            let anchorVCol = visualColumn(forDataColumn: anchor)
            guard anchorVCol >= 0 else {
                selectedWholeColumns = [dataCol]
                columnAnchor = dataCol
                updateStatus(); redrawVisible()
                return
            }
            let minV = min(anchorVCol, visualCol)
            let maxV = max(anchorVCol, visualCol)
            var cols: Set<Int> = []
            for v in minV...maxV {
                let dc = dataColumn(forVisualColumn: v)
                if dc >= 0 { cols.insert(dc) }
            }
            selectedCells.removeAll()
            selectedWholeRows.removeAll()
            selectedWholeColumns = cols
        } else {
            selectedCells.removeAll()
            selectedWholeRows.removeAll()
            selectedWholeColumns = [dataCol]
            columnAnchor = dataCol
        }
        cursor = nil
        updateStatus()
        redrawVisible()
        tableView?.headerView?.needsDisplay = true
    }

    // MARK: Select all / clear

    func selectAll() {
        selectedCells.removeAll()
        selectedWholeColumns.removeAll()
        selectedWholeRows = Set(0..<displayRowCount)
        rowAnchor = 0
        cursor = nil
        updateStatus()
        redrawVisible()
    }

    func clearSelection() {
        selectedCells.removeAll()
        selectedWholeRows.removeAll()
        selectedWholeColumns.removeAll()
        cellAnchor = nil
        rowAnchor = nil
        columnAnchor = nil
        cursor = nil
        updateStatus()
        redrawVisible()
    }

    // MARK: Keyboard navigation

    func moveCursor(dRow: Int, dCol: Int, extend: Bool) {
        guard displayRowCount > 0, !result.columns.isEmpty else { return }

        let current: CellCoord = cursor
            ?? cellAnchor
            ?? selectedCells.min(by: { $0.row == $1.row ? $0.col < $1.col : $0.row < $1.row })
            ?? CellCoord(row: 0, col: 0)

        let newRow = max(0, min(displayRowCount - 1, current.row + dRow))
        let newCol = max(0, min(result.columns.count - 1, current.col + dCol))
        let newCoord = CellCoord(row: newRow, col: newCol)

        if extend {
            let anchor = cellAnchor ?? current
            cellAnchor = anchor
            selectedWholeRows.removeAll()
            selectedWholeColumns.removeAll()
            selectedCells = rectangle(from: anchor, to: newCoord)
        } else {
            selectedWholeRows.removeAll()
            selectedWholeColumns.removeAll()
            selectedCells = [newCoord]
            cellAnchor = newCoord
        }
        cursor = newCoord
        updateStatus()
        redrawVisible()

        if let tv = tableView {
            tv.scrollRowToVisible(newRow)
            let visCol = visualColumn(forDataColumn: newCol)
            if visCol >= 0 { tv.scrollColumnToVisible(visCol) }
        }
    }

    // MARK: Helpers

    private func rectangle(from a: CellCoord, to b: CellCoord) -> Set<CellCoord> {
        let minRow = min(a.row, b.row)
        let maxRow = max(a.row, b.row)
        let minCol = min(a.col, b.col)
        let maxCol = max(a.col, b.col)
        var out: Set<CellCoord> = []
        for r in minRow...maxRow {
            for c in minCol...maxCol {
                out.insert(CellCoord(row: r, col: c))
            }
        }
        return out
    }

    private func updateStatus() {
        let hasRows = !selectedWholeRows.isEmpty
        let hasCols = !selectedWholeColumns.isEmpty
        let hasCells = !selectedCells.isEmpty

        if !hasRows && !hasCols && !hasCells {
            statusText.wrappedValue = ""
            return
        }

        // Pure single-type selections get nicer text
        if hasRows && !hasCols && !hasCells {
            statusText.wrappedValue = selectedWholeRows.count == 1
                ? "Row \(selectedWholeRows.first! + 1) selected"
                : "\(selectedWholeRows.count) rows selected"
            return
        }
        if hasCols && !hasRows && !hasCells {
            if selectedWholeColumns.count == 1, let c = selectedWholeColumns.first {
                statusText.wrappedValue = "Column \"\(result.columns[c].name)\" selected"
            } else {
                statusText.wrappedValue = "\(selectedWholeColumns.count) columns selected"
            }
            return
        }
        if hasCells && !hasRows && !hasCols {
            if selectedCells.count == 1, let cell = selectedCells.first {
                let colName = result.columns[cell.col].name
                let value = result.rows[cell.row][cell.col]
                statusText.wrappedValue = "\(colName): \(value)"
            } else {
                let rows = Set(selectedCells.map(\.row)).count
                let cols = Set(selectedCells.map(\.col)).count
                statusText.wrappedValue = "\(selectedCells.count) cells (\(rows) × \(cols))"
            }
            return
        }

        // Mixed
        var parts: [String] = []
        if hasCells { parts.append("\(selectedCells.count) cells") }
        if hasRows { parts.append("\(selectedWholeRows.count) rows") }
        if hasCols { parts.append("\(selectedWholeColumns.count) cols") }
        statusText.wrappedValue = parts.joined(separator: ", ") + " selected"
    }

    func isCellSelected(row: Int, dataCol: Int) -> Bool {
        selectedWholeRows.contains(row)
            || selectedWholeColumns.contains(dataCol)
            || selectedCells.contains(CellCoord(row: row, col: dataCol))
    }

    func isRowSelected(_ row: Int) -> Bool {
        selectedWholeRows.contains(row)
    }

    func isCursor(row: Int, dataCol: Int) -> Bool {
        cursor == CellCoord(row: row, col: dataCol)
    }

    func redrawVisible() {
        guard let tv = tableView else { return }
        let visibleRows = tv.rows(in: tv.visibleRect)
        if visibleRows.length > 0 {
            tv.reloadData(
                forRowIndexes: IndexSet(integersIn: visibleRows.location..<(visibleRows.location + visibleRows.length)),
                columnIndexes: IndexSet(integersIn: 0..<tv.numberOfColumns)
            )
        }
        tv.headerView?.needsDisplay = true
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

        let container: CellContainerView
        let tf: NSTextField

        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? CellContainerView,
           let existingTf = existing.subviews.first(where: { $0 is NSTextField }) as? NSTextField {
            container = existing
            tf = existingTf
        } else {
            container = CellContainerView()
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

        let selected = isCellSelected(row: row, dataCol: colIdx)
        let rowSelected = isRowSelected(row)

        container.layer?.backgroundColor = selected
            ? cellHighlight.cgColor
            : (rowSelected ? rowHighlight.cgColor : nil)

        container.isCursor = isCursor(row: row, dataCol: colIdx)
        container.cursorColor = cursorRing
        container.needsDisplay = true

        return container
    }

    // MARK: Copy logic

    /// Build the effective set of selected cells (expanding whole-row and whole-column selections).
    private func collectEffectiveCells() -> Set<CellCoord> {
        var effective = selectedCells
        if !selectedWholeRows.isEmpty {
            for r in selectedWholeRows {
                for c in 0..<result.columns.count {
                    effective.insert(CellCoord(row: r, col: c))
                }
            }
        }
        if !selectedWholeColumns.isEmpty {
            for c in selectedWholeColumns {
                for r in 0..<displayRowCount {
                    effective.insert(CellCoord(row: r, col: c))
                }
            }
        }
        return effective
    }

    /// Returns TSV text for the current selection, plus the number of cells copied,
    /// plus the bounding column range (for optional header prepend).
    private func buildSelectionTSV() -> (text: String, cellCount: Int, minCol: Int, maxCol: Int)? {
        // Pure whole-rows fast path — output all columns, row-ordered
        if !selectedWholeRows.isEmpty && selectedWholeColumns.isEmpty && selectedCells.isEmpty {
            let sortedRows = selectedWholeRows.sorted()
            let text = sortedRows.map { result.rows[$0].joined(separator: "\t") }.joined(separator: "\n")
            return (text, sortedRows.count * result.columns.count, 0, result.columns.count - 1)
        }
        // Pure whole-columns fast path — output all rows with only selected columns
        if !selectedWholeColumns.isEmpty && selectedWholeRows.isEmpty && selectedCells.isEmpty {
            let sortedCols = selectedWholeColumns.sorted()
            var lines: [String] = []
            for r in 0..<displayRowCount {
                lines.append(sortedCols.map { result.rows[r][$0] }.joined(separator: "\t"))
            }
            return (lines.joined(separator: "\n"), sortedCols.count * displayRowCount, sortedCols.first!, sortedCols.last!)
        }

        // General path: bounding rectangle of effective cells, empty for gaps
        let effective = collectEffectiveCells()
        if effective.isEmpty { return nil }

        let rows = effective.map(\.row)
        let cols = effective.map(\.col)
        let minRow = rows.min()!, maxRow = rows.max()!
        let minCol = cols.min()!, maxCol = cols.max()!

        var lines: [String] = []
        for r in minRow...maxRow {
            var cells: [String] = []
            for c in minCol...maxCol {
                if effective.contains(CellCoord(row: r, col: c)) {
                    cells.append(result.rows[r][c])
                } else {
                    cells.append("")
                }
            }
            lines.append(cells.joined(separator: "\t"))
        }
        return (lines.joined(separator: "\n"), effective.count, minCol, maxCol)
    }

    func copyCurrentSelection() {
        guard let (text, count, _, _) = buildSelectionTSV() else { return }
        copyToClipboard(text)
        if count == 1, let cell = selectedCells.first {
            statusText.wrappedValue = "Copied: \(result.rows[cell.row][cell.col])"
        } else {
            statusText.wrappedValue = "Copied \(count) cell\(count == 1 ? "" : "s")"
        }
        flashCopied()
    }

    func copyCurrentSelectionWithHeaders() {
        guard let (text, count, minCol, maxCol) = buildSelectionTSV() else { return }

        // Header depends on selection mode
        let headerColumns: [Int]
        if !selectedWholeColumns.isEmpty && selectedWholeRows.isEmpty && selectedCells.isEmpty {
            headerColumns = selectedWholeColumns.sorted()
        } else if !selectedWholeRows.isEmpty && selectedWholeColumns.isEmpty && selectedCells.isEmpty {
            headerColumns = Array(0..<result.columns.count)
        } else {
            headerColumns = Array(minCol...maxCol)
        }

        let header = headerColumns.map { result.columns[$0].name }.joined(separator: "\t")
        copyToClipboard(header + "\n" + text)
        statusText.wrappedValue = "Copied \(count) cell\(count == 1 ? "" : "s") with headers"
        flashCopied()
    }

    // MARK: Context menu actions

    @objc func copyCellAction(_ sender: Any?) {
        guard let tv = tableView else { return }
        let row = tv.contextRow
        let dataCol = dataColumn(forVisualColumn: tv.contextColumn)
        guard row >= 0, dataCol >= 0, dataCol < result.columns.count, row < result.rows.count else { return }
        copyToClipboard(result.rows[row][dataCol])
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
        let dataCol = dataColumn(forVisualColumn: tv.contextColumn)
        guard dataCol >= 0, dataCol < result.columns.count else { return }
        let values = (0..<displayRowCount).map { result.rows[$0][dataCol] }
        copyToClipboard(values.joined(separator: "\n"))
        statusText.wrappedValue = "Copied column \"\(result.columns[dataCol].name)\" (\(values.count) values)"
        flashCopied()
    }

    @objc func selectColumnAction(_ sender: Any?) {
        guard let tv = tableView else { return }
        handleColumnHeaderClick(visualCol: tv.contextColumn, shift: false, cmd: false)
    }

    @objc func selectRowAction(_ sender: Any?) {
        guard let tv = tableView else { return }
        handleCellClick(visualRow: tv.contextRow, visualCol: 0, shift: false, cmd: false)
    }

    @objc func selectAllAction(_ sender: Any?) {
        selectAll()
    }

    @objc func copySelectedAction(_ sender: Any?) {
        copyCurrentSelection()
    }

    @objc func copySelectedWithHeadersAction(_ sender: Any?) {
        copyCurrentSelectionWithHeaders()
    }

    @objc func copyAllAction(_ sender: Any?) {
        let header = result.columns.map(\.name).joined(separator: "\t")
        let rows = (0..<displayRowCount).map { result.rows[$0].joined(separator: "\t") }
        copyToClipboard(([header] + rows).joined(separator: "\n"))
        statusText.wrappedValue = "Copied all \(displayRowCount) rows with headers"
        flashCopied()
    }

    @objc func copyAsCSVAction(_ sender: Any?) {
        // If user has a selection, use it; otherwise everything.
        let effective = collectEffectiveCells()
        let useSelection = !effective.isEmpty

        if useSelection {
            let rows = effective.map(\.row)
            let cols = effective.map(\.col)
            let minRow = rows.min()!, maxRow = rows.max()!
            let minCol = cols.min()!, maxCol = cols.max()!
            let header = (minCol...maxCol).map { csvEscape(result.columns[$0].name) }.joined(separator: ",")
            var lines: [String] = [header]
            for r in minRow...maxRow {
                var vals: [String] = []
                for c in minCol...maxCol {
                    if effective.contains(CellCoord(row: r, col: c)) {
                        vals.append(csvEscape(result.rows[r][c]))
                    } else {
                        vals.append("")
                    }
                }
                lines.append(vals.joined(separator: ","))
            }
            copyToClipboard(lines.joined(separator: "\n"))
            statusText.wrappedValue = "Copied selection as CSV"
        } else {
            let header = result.columns.map { csvEscape($0.name) }.joined(separator: ",")
            let rows = (0..<displayRowCount).map { rowIdx in
                result.rows[rowIdx].map { csvEscape($0) }.joined(separator: ",")
            }
            copyToClipboard(([header] + rows).joined(separator: "\n"))
            statusText.wrappedValue = "Copied as CSV (\(displayRowCount) rows)"
        }
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

// MARK: - Cell container that draws a focus ring for the cursor cell

final class CellContainerView: NSView {
    var isCursor: Bool = false {
        didSet { if oldValue != isCursor { needsDisplay = true } }
    }
    var cursorColor: NSColor = NSColor.controlAccentColor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isCursor {
            let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            cursorColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }
}

// MARK: - Custom NSTableView with cell-level selection

class DataGridTableView: NSTableView {
    weak var gridCoordinator: DataGridCoordinator?

    var contextColumn: Int = -1
    var contextRow: Int = -1

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        let clickedCol = column(at: point)
        let shift = event.modifierFlags.contains(.shift)
        let cmd = event.modifierFlags.contains(.command)

        // Make sure we're first responder so Cmd+C works
        window?.makeFirstResponder(self)

        guard clickedRow >= 0, clickedCol >= 0 else {
            if !shift && !cmd {
                gridCoordinator?.clearSelection()
            }
            return
        }

        // Initial click
        gridCoordinator?.handleCellClick(visualRow: clickedRow, visualCol: clickedCol, shift: shift, cmd: cmd)

        // Modifier clicks don't start a drag (they're toggle/extend)
        if cmd {
            return
        }

        // Track drag for rectangular selection
        let anchorRow = clickedRow
        let anchorCol = clickedCol
        var lastRow = clickedRow
        var lastCol = clickedCol

        while let nextEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if nextEvent.type == .leftMouseUp { break }

            autoscroll(with: nextEvent)

            let newPoint = convert(nextEvent.locationInWindow, from: nil)
            var newRow = row(at: newPoint)
            var newCol = column(at: newPoint)

            // Clamp to visible bounds
            if newRow < 0 {
                newRow = newPoint.y < 0 ? 0 : (numberOfRows - 1)
            }
            if newCol < 0 {
                newCol = newPoint.x < 0 ? 0 : (numberOfColumns - 1)
            }

            if newRow == lastRow && newCol == lastCol { continue }
            lastRow = newRow
            lastCol = newCol

            gridCoordinator?.handleDragSelection(
                startVisualRow: anchorRow,
                startVisualCol: anchorCol,
                endVisualRow: newRow,
                endVisualCol: newCol
            )
        }
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

        // Copy Selection — always available, with keybind hint
        let selItem = NSMenuItem(title: "Copy Selection", action: #selector(DataGridCoordinator.copySelectedAction(_:)), keyEquivalent: "c")
        selItem.keyEquivalentModifierMask = .command
        selItem.target = coordinator
        selItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
        menu.addItem(selItem)

        let selHdrItem = NSMenuItem(title: "Copy Selection with Headers", action: #selector(DataGridCoordinator.copySelectedWithHeadersAction(_:)), keyEquivalent: "c")
        selHdrItem.keyEquivalentModifierMask = [.command, .shift]
        selHdrItem.target = coordinator
        menu.addItem(selHdrItem)

        // Copy All
        let allItem = NSMenuItem(title: "Copy All with Headers", action: #selector(DataGridCoordinator.copyAllAction(_:)), keyEquivalent: "")
        allItem.target = coordinator
        menu.addItem(allItem)

        menu.addItem(.separator())

        // Select submenu
        let selectSub = NSMenu()
        let selectRow = NSMenuItem(title: "Select Row", action: #selector(DataGridCoordinator.selectRowAction(_:)), keyEquivalent: "")
        selectRow.target = coordinator
        selectSub.addItem(selectRow)

        if contextColumn >= 1 {
            let selectCol = NSMenuItem(title: "Select Column", action: #selector(DataGridCoordinator.selectColumnAction(_:)), keyEquivalent: "")
            selectCol.target = coordinator
            selectSub.addItem(selectCol)
        }

        let selectAll = NSMenuItem(title: "Select All", action: #selector(DataGridCoordinator.selectAllAction(_:)), keyEquivalent: "a")
        selectAll.keyEquivalentModifierMask = .command
        selectAll.target = coordinator
        selectSub.addItem(selectAll)

        let selectItem = NSMenuItem(title: "Select", action: nil, keyEquivalent: "")
        selectItem.submenu = selectSub
        menu.addItem(selectItem)

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
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let chars = event.charactersIgnoringModifiers ?? ""

        if cmd && chars == "c" {
            if shift {
                gridCoordinator?.copyCurrentSelectionWithHeaders()
            } else {
                gridCoordinator?.copyCurrentSelection()
            }
            return
        }
        if cmd && chars == "a" {
            gridCoordinator?.selectAll()
            return
        }

        // Arrow keys for navigation
        switch event.keyCode {
        case 123: // left
            gridCoordinator?.moveCursor(dRow: 0, dCol: -1, extend: shift)
            return
        case 124: // right
            gridCoordinator?.moveCursor(dRow: 0, dCol: 1, extend: shift)
            return
        case 125: // down
            gridCoordinator?.moveCursor(dRow: 1, dCol: 0, extend: shift)
            return
        case 126: // up
            gridCoordinator?.moveCursor(dRow: -1, dCol: 0, extend: shift)
            return
        default:
            break
        }

        super.keyDown(with: event)
    }

    // Disable built-in row highlight drawing — we draw our own cell highlights
    override func highlightSelection(inClipRect clipRect: NSRect) {
        // intentionally empty
    }
}

// MARK: - Header view that selects entire columns on click

class DataGridHeaderView: NSTableHeaderView {
    weak var gridCoordinator: DataGridCoordinator?

    override func mouseDown(with event: NSEvent) {
        guard let tv = tableView else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let clickedCol = column(at: point)

        guard clickedCol >= 0 else {
            super.mouseDown(with: event)
            return
        }

        // Preserve column resize: if click is near the right edge, let AppKit handle it
        let colRect = headerRect(ofColumn: clickedCol)
        if colRect.maxX - point.x < 5 || (clickedCol > 0 && point.x - colRect.minX < 3) {
            super.mouseDown(with: event)
            return
        }

        // Make sure the table becomes first responder so Cmd+C / arrow keys work
        tv.window?.makeFirstResponder(tv)

        let shift = event.modifierFlags.contains(.shift)
        let cmd = event.modifierFlags.contains(.command)
        gridCoordinator?.handleColumnHeaderClick(visualCol: clickedCol, shift: shift, cmd: cmd)
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
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true

        let headerView = DataGridHeaderView()
        headerView.gridCoordinator = context.coordinator
        tableView.headerView = headerView

        buildColumns(tableView: tableView, result: result)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        context.coordinator.tableView = tableView

        scrollView.documentView = tableView

        // Make the table first responder so Cmd+C works without a prior click
        DispatchQueue.main.async {
            tableView.window?.makeFirstResponder(tableView)
        }

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
            coordinator.clearSelection()
            tableView.gridCoordinator = coordinator
            (tableView.headerView as? DataGridHeaderView)?.gridCoordinator = coordinator

            while tableView.tableColumns.count > 0 {
                tableView.removeTableColumn(tableView.tableColumns[0])
            }

            buildColumns(tableView: tableView, result: newResult)
            tableView.reloadData()

            DispatchQueue.main.async {
                tableView.window?.makeFirstResponder(tableView)
            }
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
