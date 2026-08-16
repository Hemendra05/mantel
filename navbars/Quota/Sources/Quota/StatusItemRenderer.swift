import AppKit

/// Two concentric arcs: outer is the session limit, inner is the week. Both sweep
/// clockwise from 12 o'clock. Template-rendered, so it tints with the menu bar and
/// carries two numbers without any text.
@MainActor
enum StatusItemRenderer {
    static let size: CGFloat = 16
    private static let line: CGFloat = 1.8

    static var outerRadius: CGFloat { size / 2 - line / 2 - 0.5 }
    static var innerRadius: CGFloat { outerRadius - line - 1.6 }

    static func image(signedIn: Bool, session: Double? = nil, week: Double? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let center = NSPoint(x: size / 2, y: size / 2)

            guard signedIn else {
                let path = circle(center: center, radius: outerRadius)
                path.lineWidth = line
                path.setLineDash([2, 2.2], count: 2, phase: 0)
                NSColor.black.withAlphaComponent(0.5).setStroke()
                path.stroke()
                return true
            }

            ring(center: center, radius: outerRadius, fraction: session)
            ring(center: center, radius: innerRadius, fraction: week)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func circle(center: NSPoint, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2))
    }

    private static func ring(center: NSPoint, radius: CGFloat, fraction: Double?) {
        let track = circle(center: center, radius: radius)
        track.lineWidth = line
        NSColor.black.withAlphaComponent(0.22).setStroke()
        track.stroke()

        guard let fraction, fraction > 0.005 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                      endAngle: 90 - 360 * min(fraction, 1), clockwise: true)
        arc.lineWidth = line
        arc.lineCapStyle = .round
        NSColor.black.setStroke()
        arc.stroke()
    }
}
