import AppKit

/// The menu bar glyph: a CPU sparkline over a memory meter, no text and no colour.
/// Always template-rendered so macOS tints it exactly like the system icons beside
/// it — detail belongs in the panel, not the menu bar.
@MainActor
enum StatusItemRenderer {
    nonisolated static let historyLength = 24

    private static let width: CGFloat = 24
    private static let sparkHeight: CGFloat = 9
    private static let meterHeight: CGFloat = 2.5
    private static let gap: CGFloat = 2.5
    private static let height: CGFloat = sparkHeight + gap + meterHeight

    static func image(cpuHistory: [Double], memHistory: [Double]) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            spark(cpuHistory, y: meterHeight + gap)
            meter(memHistory.last ?? 0, y: 0)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Filled silhouette, newest sample pinned to the right so the shape does not
    /// slide while history fills.
    private static func spark(_ history: [Double], y: CGFloat) {
        guard let last = history.last else { return }
        let samples = Array(history.suffix(Int(width)))
        let step = width / CGFloat(max(Int(width) - 1, 1))
        let offset = width - step * CGFloat(max(samples.count - 1, 0))

        func point(_ i: Int) -> NSPoint {
            NSPoint(x: offset + step * CGFloat(i),
                    y: y + sparkHeight * min(max(samples[i], 0), 1))
        }

        let path = NSBezierPath()
        path.move(to: NSPoint(x: offset, y: y))
        if samples.count == 1 {
            path.line(to: NSPoint(x: offset, y: y + sparkHeight * min(max(last, 0), 1)))
            path.line(to: NSPoint(x: width, y: y + sparkHeight * min(max(last, 0), 1)))
        } else {
            for i in 0..<samples.count { path.line(to: point(i)) }
        }
        path.line(to: NSPoint(x: width, y: y))
        path.close()

        NSColor.black.withAlphaComponent(0.20).setFill()
        path.fill()

        // A crisp top edge keeps the shape legible when the fill is short.
        let edge = NSBezierPath()
        for i in 0..<samples.count {
            i == 0 ? edge.move(to: point(i)) : edge.line(to: point(i))
        }
        NSColor.black.setStroke()
        edge.lineWidth = 1
        edge.lineJoinStyle = .round
        edge.stroke()
    }

    private static func meter(_ value: Double, y: CGFloat) {
        let radius = meterHeight / 2
        let track = NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: width, height: meterHeight),
                                 xRadius: radius, yRadius: radius)
        NSColor.black.withAlphaComponent(0.3).setFill()
        track.fill()

        let filled = max(meterHeight, width * min(max(value, 0), 1))
        let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: filled, height: meterHeight),
                                xRadius: radius, yRadius: radius)
        NSColor.black.setFill()
        fill.fill()
    }
}
