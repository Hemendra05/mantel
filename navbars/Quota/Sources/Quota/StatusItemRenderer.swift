import AppKit

/// A ring glyph: solid when signed in, hollow when not. The ring is drawn as an arc
/// so a usage fraction can later sweep it without changing the silhouette.
@MainActor
enum StatusItemRenderer {
    private static let size: CGFloat = 15
    private static let lineWidth: CGFloat = 1.6

    static func image(signedIn: Bool, fraction: Double? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let inset = lineWidth / 2 + 0.5
            let rect = NSRect(x: inset, y: inset,
                              width: size - inset * 2, height: size - inset * 2)
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2

            let track = NSBezierPath(ovalIn: rect)
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(signedIn ? 0.3 : 0.55).setStroke()
            if !signedIn {
                track.setLineDash([2, 2], count: 2, phase: 0)
            }
            track.stroke()

            guard signedIn else { return true }

            // Full sweep until a real usage fraction is available.
            let sweep = min(max(fraction ?? 1, 0), 1)
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius,
                          startAngle: 90, endAngle: 90 - 360 * sweep, clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()

            let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 1.6, y: center.y - 1.6,
                                                  width: 3.2, height: 3.2))
            NSColor.black.setFill()
            dot.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
