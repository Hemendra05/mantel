import AppKit
import Foundation
import SwiftUI

/// `Pulse --dump` prints one sampled snapshot as text, for cross-checking the
/// kernel counters against vm_stat / top without launching the UI.
enum Dump {
    static func run() {
        let metrics = SystemMetrics()
        _ = metrics.sample()                 // prime the CPU tick delta
        Thread.sleep(forTimeInterval: 1.0)
        let snap = metrics.sample()
        let mem = snap.memory

        print("cpu.busy      \(pct(snap.cpu.busy))")
        print("cpu.user      \(pct(snap.cpu.user))")
        print("cpu.system    \(pct(snap.cpu.system))")
        print("cpu.nice      \(pct(snap.cpu.nice))")
        print("cpu.cores     \(snap.coreCount) (\(snap.perfCores)P + \(snap.effCores)E)")
        print("cpu.perCore   " + snap.cpu.perCore.map { pct($0) }.joined(separator: " "))
        print(String(format: "load          %.2f %.2f %.2f",
                     snap.loadAverage.0, snap.loadAverage.1, snap.loadAverage.2))
        print("")
        print("mem.total     \(bytes(mem.total))")
        print("mem.used      \(bytes(mem.used))   (\(pct(mem.usedFraction)))  [= total - cached - free, as Activity Monitor]")
        print("mem.app       \(bytes(mem.app))")
        print("mem.wired     \(bytes(mem.wired))")
        print("mem.compress  \(bytes(mem.compressed))")
        print("mem.other     \(bytes(mem.other))   [kernel etc; AM does not itemise this]")
        print("  sum parts   \(bytes(mem.app + mem.wired + mem.compressed + mem.other))")
        print("mem.cached    \(bytes(mem.cached))")
        print("mem.free      \(bytes(mem.free))")
        print("mem.swap      \(bytes(mem.swapUsed)) / \(bytes(mem.swapTotal))")
        print("mem.pressure  \(mem.pressureLevel) (\(Fmt.pressure(mem.pressureLevel)))")
        print("uptime        \(Fmt.uptime(snap.uptime))")
    }

    /// Writes the menu bar glyph to a PNG, magnified on a neutral backdrop so the
    /// template (alpha-only) rendering is actually inspectable.
    @MainActor
    static func glyph(to path: String, scale: CGFloat = 10) {
        let cpu: [Double] = (0..<StatusItemRenderer.historyLength).map { (i: Int) -> Double in
            let t = Double(i)
            return 0.35 + 0.45 * sin(t / 4.0) * sin(t / 11.0)
        }
        let mem: [Double] = (0..<StatusItemRenderer.historyLength).map { (i: Int) -> Double in
            0.58 + 0.06 * sin(Double(i) / 7.0)
        }
        // Four load levels, so the glyph can be judged across its whole range.
        let states: [(Double, Double)] = [(0.08, 0.35), (0.35, 0.57), (0.7, 0.75), (1.0, 0.95)]
        let glyphs = states.map { cpuLevel, memLevel in
            StatusItemRenderer.image(
                cpuHistory: cpu.map { min(1, max(0, $0 * cpuLevel + cpuLevel * 0.35)) },
                memHistory: mem.map { _ in memLevel })
        }
        let normal = glyphs[1]
        let unit = NSSize(width: normal.size.width * scale, height: normal.size.height * scale)
        let size = NSSize(width: unit.width, height: unit.height * CGFloat(glyphs.count)
                          + scale * CGFloat(glyphs.count - 1))

        let canvas = NSImage(size: size, flipped: false) { rect in
            NSColor(white: 0.88, alpha: 1).setFill()
            rect.fill()
            NSGraphicsContext.current?.imageInterpolation = .none
            for (i, glyph) in glyphs.reversed().enumerated() {
                let y = (unit.height + scale) * CGFloat(i)
                glyph.draw(in: NSRect(x: 0, y: y, width: unit.width, height: unit.height))
            }
            return true
        }
        guard let tiff = canvas.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            print("failed to encode glyph"); return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("glyph \(Int(normal.size.width))x\(Int(normal.size.height))pt (4 load levels) -> \(path)")
    }

    /// Renders the panel itself to a PNG in both colour schemes via ImageRenderer,
    /// so the design can be reviewed without clicking the status item.
    @MainActor
    static func panel(to path: String) {
        let model = PulseModel()
        model.start()
        model.panelVisible = true
        model.refreshProcesses()
        // Let a timer tick and the ps sample land so the panel is fully populated.
        RunLoop.current.run(until: Date().addingTimeInterval(1.6))

        // Real snapshot, synthesised history so the sparkline has a shape to judge.
        model.cpuHistory = (0..<StatusItemRenderer.historyLength).map { (i: Int) -> Double in
            let t = Double(i)
            let wave: Double = 0.42 + 0.34 * sin(t / 3.4) * sin(t / 9.0) + 0.1 * sin(t / 1.7)
            return min(0.97, max(0.04, wave))
        }
        model.memHistory = (0..<StatusItemRenderer.historyLength).map { (i: Int) -> Double in
            0.56 + 0.04 * sin(Double(i) / 6.0)
        }

        let shots: [(ColorScheme, NSColor)] = [
            (.dark, NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)),
            (.light, NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)),
        ]

        var images: [NSImage] = []
        for (scheme, _) in shots {
            let renderer = ImageRenderer(
                content: PulsePanel(model: model).environment(\.colorScheme, scheme))
            renderer.scale = 2
            if let image = renderer.nsImage { images.append(image) }
        }
        guard images.count == shots.count else { print("render failed"); return }

        let pad: CGFloat = 16
        let unit = images[0].size
        let canvas = NSImage(
            size: NSSize(width: (unit.width + pad * 2) * 2, height: unit.height + pad * 2),
            flipped: false) { _ in
            for (i, image) in images.enumerated() {
                let originX = (unit.width + pad * 2) * CGFloat(i)
                shots[i].1.setFill()
                NSRect(x: originX, y: 0, width: unit.width + pad * 2,
                       height: unit.height + pad * 2).fill()
                image.draw(in: NSRect(x: originX + pad, y: pad,
                                      width: unit.width, height: unit.height))
            }
            return true
        }
        guard let tiff = canvas.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            print("failed to encode panel"); return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("panel \(Int(unit.width))x\(Int(unit.height))pt (dark | light) -> \(path)")
    }

    private static func pct(_ value: Double) -> String {
        String(format: "%5.1f%%", value * 100)
    }

    private static func bytes(_ value: UInt64) -> String {
        String(format: "%10.2f GB", Double(value) / 1_073_741_824)
    }
}
