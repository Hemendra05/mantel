import AppKit
import Foundation
import SwiftUI

/// Headless verification, as in Pulse: screencapture is TCC-blocked from a terminal.
enum QuotaDump {
    static func run() {
        print("claude binary  \(ClaudeCLI.locate()?.path ?? "NOT FOUND")")
        do {
            let status = try ClaudeCLI.authStatus()
            print("loggedIn       \(status.loggedIn)")
            print("authMethod     \(status.authMethod ?? "—")")
            print("apiProvider    \(status.apiProvider ?? "—")")
            print("subscription   \(status.subscriptionType ?? "—")")
            print("orgName        \(status.orgName ?? "—")")
            // Account identifiers are masked: --dump output tends to get pasted.
            print("email          \(mask(status.email))")
            print("orgId          \(mask(status.orgId))")
        } catch {
            print("error          \((error as? CLIError)?.errorDescription ?? "\(error)")")
        }
        print("")
        do {
            let usage = try ClaudeCLI.usage()
            print("usage.note     \(usage.note ?? "—")")
            if usage.limits.isEmpty { print("usage          (no limits parsed)") }
            for limit in usage.limits {
                print(String(format: "  %-22s %3d%%  resets %@",
                             (limit.label as NSString).utf8String!, limit.percent,
                             limit.resets ?? "—"))
            }
        } catch {
            print("usage.error    \((error as? CLIError)?.errorDescription ?? "\(error)")")
        }
    }

    private static func mask(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        if let at = value.firstIndex(of: "@") {
            return "\(value.prefix(2))***\(value[at...])"
        }
        return "\(value.prefix(4))…\(value.suffix(4))"
    }

    @MainActor
    static func glyph(to path: String, scale: CGFloat = 10) {
        let glyphs = [
            StatusItemRenderer.image(signedIn: true, session: 0.15, week: 0.08),
            StatusItemRenderer.image(signedIn: true, session: 0.48, week: 0.21),
            StatusItemRenderer.image(signedIn: true, session: 0.92, week: 0.60),
            StatusItemRenderer.image(signedIn: false),
        ]
        let unit = NSSize(width: glyphs[0].size.width * scale,
                          height: glyphs[0].size.height * scale)
        let canvas = NSImage(size: NSSize(width: unit.width,
                                          height: (unit.height + scale) * CGFloat(glyphs.count)),
                             flipped: false) { rect in
            NSColor(white: 0.88, alpha: 1).setFill()
            rect.fill()
            for (i, glyph) in glyphs.reversed().enumerated() {
                glyph.draw(in: NSRect(x: 0, y: (unit.height + scale) * CGFloat(i),
                                      width: unit.width, height: unit.height))
            }
            return true
        }
        write(canvas, to: path, label: "glyph (session/week: 15/8, 48/21, 92/60, signed out)")
    }

    @MainActor
    static func panel(to path: String) {
        let model = QuotaModel()
        model.refresh()
        // The usage call spawns the CLI for ~4s; render only once it has landed.
        let deadline = Date().addingTimeInterval(30)
        while model.refreshing, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        let shots: [(ColorScheme, NSColor)] = [
            (.dark, NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)),
            (.light, NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)),
        ]
        var images: [NSImage] = []
        for (scheme, _) in shots {
            let renderer = ImageRenderer(
                content: QuotaPanel(model: model).environment(\.colorScheme, scheme))
            renderer.scale = 2
            if let image = renderer.nsImage { images.append(image) }
        }
        guard images.count == shots.count else { print("render failed"); return }

        let pad: CGFloat = 16
        let unit = images[0].size
        let canvas = NSImage(size: NSSize(width: (unit.width + pad * 2) * 2,
                                          height: unit.height + pad * 2),
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
        write(canvas, to: path, label: "panel (dark | light)")
    }

    private static func write(_ image: NSImage, to path: String, label: String) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png,
                                           properties: [:]) else {
            print("failed to encode \(label)"); return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("\(label) -> \(path)")
    }
}
