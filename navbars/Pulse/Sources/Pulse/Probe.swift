import AppKit
import SwiftUI

/// `Pulse --probe` shows the panel programmatically and prints its geometry, so
/// popover placement can be debugged without clicking (screencapture is TCC-blocked).
@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private let model = PulseModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusItemRenderer.image(
            cpuHistory: [0.5], memHistory: [0.5])

        let host = NSHostingController(rootView: PulsePanel(model: model))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        model.start()
        model.panelVisible = true
        model.refreshProcesses()

        // Let the process sample land so the panel is at its full height.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [self] in
            guard let button = statusItem.button else { return }
            let edges: [(String, NSRectEdge)] = [
                ("minY", .minY), ("maxY", .maxY), ("minX", .minX), ("maxX", .maxX),
            ]
            let name = CommandLine.arguments.last ?? "minY"
            let edge = edges.first { $0.0 == name }?.1 ?? .minY
            print("preferredEdge       \(edges.first { $0.1 == edge }?.0 ?? "?")")
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: edge)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                report(host: host, button: button)
                NSApp.terminate(nil)
            }
        }
    }

    private func report(host: NSHostingController<PulsePanel>, button: NSStatusBarButton) {
        func r(_ rect: NSRect) -> String {
            String(format: "x=%.0f y=%.0f w=%.0f h=%.0f",
                   rect.origin.x, rect.origin.y, rect.width, rect.height)
        }
        let screen = button.window?.screen ?? NSScreen.main
        print("screen.frame        \(r(screen?.frame ?? .zero))")
        print("screen.visibleFrame \(r(screen?.visibleFrame ?? .zero))")
        print("statusButton.window \(r(button.window?.frame ?? .zero))")
        print("popover.contentSize w=\(Int(popover.contentSize.width)) h=\(Int(popover.contentSize.height))")
        print("host.view.frame     \(r(host.view.frame))")
        print("host.fittingSize    w=\(Int(host.view.fittingSize.width)) h=\(Int(host.view.fittingSize.height))")
        if let window = host.view.window {
            print("popover.window      \(r(window.frame))")
            let top = window.frame.maxY
            let screenTop = screen?.frame.maxY ?? 0
            print("popover top vs screen top: \(String(format: "%.0f", top)) vs \(String(format: "%.0f", screenTop))")
            if window.frame.minY < (screen?.frame.minY ?? 0) {
                print("!! popover extends BELOW screen bottom by \(String(format: "%.0f", (screen?.frame.minY ?? 0) - window.frame.minY))pt")
            }
            if top > screenTop {
                print("!! popover extends ABOVE screen top by \(String(format: "%.0f", top - screenTop))pt")
            }
        } else {
            print("popover.window      <nil>")
        }
    }
}
