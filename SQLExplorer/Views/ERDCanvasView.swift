import SwiftUI
import AppKit

// MARK: - SwiftUI Representable

struct ERDCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var schema: ERDSchema

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.15
        scrollView.maxMagnification = 3.0
        scrollView.magnification = 0.6

        let canvas = ERDCanvasNSView(schema: schema)
        canvas.frame = NSRect(x: 0, y: 0, width: 6000, height: 6000)
        scrollView.documentView = canvas
        context.coordinator.canvas = canvas

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.canvas?.schema = schema
        context.coordinator.canvas?.needsDisplay = true
        // Resize canvas if needed
        let needed = computeCanvasSize()
        if let canvas = context.coordinator.canvas {
            let newSize = NSSize(width: max(needed.width, 2000), height: max(needed.height, 2000))
            if canvas.frame.size != newSize {
                canvas.frame.size = newSize
            }
        }
    }

    private func computeCanvasSize() -> NSSize {
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for table in schema.tables {
            let h = ERDCanvasNSView.tableHeight(table)
            maxX = max(maxX, table.position.x + ERDCanvasNSView.tableWidth + 100)
            maxY = max(maxY, table.position.y + h + 100)
        }
        return NSSize(width: maxX, height: maxY)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        weak var canvas: ERDCanvasNSView?
    }
}

// MARK: - Core Canvas NSView

class ERDCanvasNSView: NSView {
    var schema: ERDSchema
    private var dragTable: ERDTable?
    private var dragOffset: CGPoint = .zero

    static let tableWidth: CGFloat = 220
    static let headerHeight: CGFloat = 28
    static let rowHeight: CGFloat = 20
    static let cornerRadius: CGFloat = 6

    private let headerColor = NSColor(red: 0.08, green: 0.35, blue: 0.72, alpha: 1) // SSMS-style blue
    private let tableBg = NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1)
    private let tableBorder = NSColor(red: 0.25, green: 0.27, blue: 0.30, alpha: 1)
    private let canvasBg = NSColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
    private let headerFont = NSFont.systemFont(ofSize: 11, weight: .bold)
    private let colFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    private let typeFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
    private let pkColor = NSColor.systemYellow
    private let fkColor = NSColor.systemCyan
    private let lineColor = NSColor(red: 0.45, green: 0.50, blue: 0.55, alpha: 0.8)

    override var isFlipped: Bool { true }

    init(schema: ERDSchema) {
        self.schema = schema
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func tableHeight(_ table: ERDTable) -> CGFloat {
        headerHeight + CGFloat(table.columns.count) * rowHeight + 4
    }

    private func tableRect(_ table: ERDTable) -> NSRect {
        NSRect(x: table.position.x, y: table.position.y,
               width: Self.tableWidth, height: Self.tableHeight(table))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background
        ctx.setFillColor(canvasBg.cgColor)
        ctx.fill(dirtyRect)

        // Draw grid dots
        drawGrid(ctx, dirtyRect: dirtyRect)

        // Draw relationship lines first (behind tables)
        for rel in schema.relationships {
            drawRelationship(ctx, rel)
        }

        // Draw tables
        for table in schema.tables {
            drawTable(ctx, table)
        }
    }

    private func drawGrid(_ ctx: CGContext, dirtyRect: NSRect) {
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.03).cgColor)
        let spacing: CGFloat = 40
        let startX = floor(dirtyRect.minX / spacing) * spacing
        let startY = floor(dirtyRect.minY / spacing) * spacing
        var x = startX
        while x < dirtyRect.maxX {
            var y = startY
            while y < dirtyRect.maxY {
                ctx.fill(CGRect(x: x, y: y, width: 1.5, height: 1.5))
                y += spacing
            }
            x += spacing
        }
    }

    private func drawTable(_ ctx: CGContext, _ table: ERDTable) {
        let rect = tableRect(table)

        // Shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        let path = CGPath(roundedRect: rect, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
        ctx.setFillColor(tableBg.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        // Border
        ctx.setStrokeColor(tableBorder.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // Header bar
        let headerRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: Self.headerHeight)
        let headerPath = CGMutablePath()
        headerPath.move(to: CGPoint(x: rect.minX + Self.cornerRadius, y: rect.minY))
        headerPath.addLine(to: CGPoint(x: rect.maxX - Self.cornerRadius, y: rect.minY))
        headerPath.addArc(center: CGPoint(x: rect.maxX - Self.cornerRadius, y: rect.minY + Self.cornerRadius), radius: Self.cornerRadius, startAngle: -.pi/2, endAngle: 0, clockwise: false)
        headerPath.addLine(to: CGPoint(x: rect.maxX, y: headerRect.maxY))
        headerPath.addLine(to: CGPoint(x: rect.minX, y: headerRect.maxY))
        headerPath.addLine(to: CGPoint(x: rect.minX, y: rect.minY + Self.cornerRadius))
        headerPath.addArc(center: CGPoint(x: rect.minX + Self.cornerRadius, y: rect.minY + Self.cornerRadius), radius: Self.cornerRadius, startAngle: .pi, endAngle: -.pi/2, clockwise: false)
        headerPath.closeSubpath()

        ctx.setFillColor(headerColor.cgColor)
        ctx.addPath(headerPath)
        ctx.fillPath()

        // Header text
        let headerStr = NSAttributedString(string: table.fullName, attributes: [
            .font: headerFont,
            .foregroundColor: NSColor.white
        ])
        headerStr.draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 7))

        // Columns
        for (i, col) in table.columns.enumerated() {
            let y = rect.minY + Self.headerHeight + CGFloat(i) * Self.rowHeight + 2

            // Alternating row bg
            if i % 2 == 1 {
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.02).cgColor)
                ctx.fill(CGRect(x: rect.minX + 1, y: y, width: rect.width - 2, height: Self.rowHeight))
            }

            // PK/FK indicator
            var iconX = rect.minX + 6
            if col.isPrimaryKey {
                let keyStr = NSAttributedString(string: "PK", attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: pkColor
                ])
                keyStr.draw(at: CGPoint(x: iconX, y: y + 3))
            } else if col.isForeignKey {
                let fkStr = NSAttributedString(string: "FK", attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: fkColor
                ])
                fkStr.draw(at: CGPoint(x: iconX, y: y + 3))
            }
            iconX += 20

            // Column name
            let nameStr = NSAttributedString(string: col.name, attributes: [
                .font: colFont,
                .foregroundColor: NSColor.labelColor
            ])
            nameStr.draw(at: CGPoint(x: iconX, y: y + 3))

            // Data type (right-aligned)
            let typeStr = NSAttributedString(string: col.dataType, attributes: [
                .font: typeFont,
                .foregroundColor: NSColor.tertiaryLabelColor
            ])
            let typeSize = typeStr.size()
            typeStr.draw(at: CGPoint(x: rect.maxX - typeSize.width - 8, y: y + 4))
        }
    }

    private func drawRelationship(_ ctx: CGContext, _ rel: ERDRelationship) {
        guard let fromTable = schema.tables.first(where: { $0.fullName == rel.fromTable }),
              let toTable = schema.tables.first(where: { $0.fullName == rel.toTable }) else { return }

        let fromRect = tableRect(fromTable)
        let toRect = tableRect(toTable)

        // Connect from right edge of source to left edge of target (or vice versa)
        let fromCenterY = fromRect.midY
        let toCenterY = toRect.midY

        let startX: CGFloat
        let endX: CGFloat
        let midX: CGFloat

        if fromRect.midX < toRect.midX {
            startX = fromRect.maxX
            endX = toRect.minX
            midX = (startX + endX) / 2
        } else {
            startX = fromRect.minX
            endX = toRect.maxX
            midX = (startX + endX) / 2
        }

        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Orthogonal routing
        ctx.beginPath()
        ctx.move(to: CGPoint(x: startX, y: fromCenterY))
        ctx.addLine(to: CGPoint(x: midX, y: fromCenterY))
        ctx.addLine(to: CGPoint(x: midX, y: toCenterY))
        ctx.addLine(to: CGPoint(x: endX, y: toCenterY))
        ctx.strokePath()

        // Arrow head at target end
        let arrowSize: CGFloat = 6
        let arrowDir: CGFloat = endX > midX ? -1 : 1
        ctx.setFillColor(lineColor.cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: endX, y: toCenterY))
        ctx.addLine(to: CGPoint(x: endX + arrowDir * arrowSize, y: toCenterY - arrowSize / 2))
        ctx.addLine(to: CGPoint(x: endX + arrowDir * arrowSize, y: toCenterY + arrowSize / 2))
        ctx.closePath()
        ctx.fillPath()

        // Small diamond at source (FK end)
        let dSize: CGFloat = 4
        let dDir: CGFloat = startX < midX ? 1 : -1
        ctx.beginPath()
        ctx.move(to: CGPoint(x: startX, y: fromCenterY))
        ctx.addLine(to: CGPoint(x: startX + dDir * dSize, y: fromCenterY - dSize))
        ctx.addLine(to: CGPoint(x: startX + dDir * dSize * 2, y: fromCenterY))
        ctx.addLine(to: CGPoint(x: startX + dDir * dSize, y: fromCenterY + dSize))
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: Mouse interaction (drag tables)

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for table in schema.tables.reversed() {
            if tableRect(table).contains(point) {
                dragTable = table
                dragOffset = CGPoint(x: point.x - table.position.x, y: point.y - table.position.y)
                return
            }
        }
        dragTable = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let table = dragTable else { return }
        let point = convert(event.locationInWindow, from: nil)
        table.position = CGPoint(
            x: max(0, point.x - dragOffset.x),
            y: max(0, point.y - dragOffset.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragTable = nil
    }
}
