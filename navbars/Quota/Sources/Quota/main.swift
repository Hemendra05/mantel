import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = QuotaModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: QuotaPanel(model: model))
        // Without this the popover keeps a stale default content size, clipping the
        // panel and pushing it off the top of the screen.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        model.onUpdate = { [weak self] in self?.redraw() }
        model.start()
        redraw()
    }

    private func redraw() {
        statusItem.button?.image = StatusItemRenderer.image(signedIn: model.status.loggedIn)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

let args = CommandLine.arguments
if args.contains("--dump") {
    QuotaDump.run()
} else if let i = args.firstIndex(of: "--panel"), i + 1 < args.count {
    QuotaDump.panel(to: args[i + 1])
} else if let i = args.firstIndex(of: "--glyph"), i + 1 < args.count {
    QuotaDump.glyph(to: args[i + 1])
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
