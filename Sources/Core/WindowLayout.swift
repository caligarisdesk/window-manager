import CoreGraphics

/// Window placement math. AppKit screen frames have a bottom-left origin; Terminal's AppleScript
/// bounds have a top-left origin at the primary screen, so every conversion needs that screen's height.
struct WindowLayout {
    /// Height of the primary (menu bar) screen.
    var primaryHeight: CGFloat
    /// Usable area (AppKit coordinates) of the screen windows are arranged on.
    var frame: CGRect

    func bounds(from rect: CGRect) -> WindowBounds {
        let top = primaryHeight - rect.maxY
        return WindowBounds(left: Int(rect.minX), top: Int(top), right: Int(rect.maxX), bottom: Int(top + rect.height))
    }

    /// Nearly the whole screen, for an expanded window.
    func expanded(inset: CGFloat = 12) -> WindowBounds {
        bounds(from: frame.insetBy(dx: inset, dy: inset))
    }

    /// A grid of `count` cells filling the frame, row by row from the top-left. Columns are chosen so
    /// cells come out landscape-shaped (roughly 1.6:1) like a terminal.
    func grid(count: Int, gap: CGFloat = 8) -> [WindowBounds] {
        guard count > 0 else { return [] }
        let area = frame.insetBy(dx: gap, dy: gap)
        let (cols, rows) = Self.gridShape(count: count, aspect: Double(area.width / area.height))
        let w = (area.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let h = (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return (0..<count).map { i in
            let row = i / cols, col = i % cols
            let x = area.minX + CGFloat(col) * (w + gap)
            let top = area.maxY - CGFloat(row) * (h + gap)
            return bounds(from: CGRect(x: x, y: top - h, width: w, height: h))
        }
    }

    static func gridShape(count: Int, aspect: Double) -> (cols: Int, rows: Int) {
        let cols = min(count, max(1, Int((Double(count) * aspect / 1.6).squareRoot().rounded(.up))))
        let rows = Int((Double(count) / Double(cols)).rounded(.up))
        return (cols, rows)
    }
}
