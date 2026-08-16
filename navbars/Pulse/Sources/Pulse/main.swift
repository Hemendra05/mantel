import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = PulseModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: PulsePanel(model: model))
        // Without this the popover keeps a stale 320x320 content size, which both
        // clips the panel and pushes it above the top of the screen.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        model.onUpdate = { [weak self] in self?.redraw() }
        model.start()
        redraw()
    }

    private func redraw() {
        statusItem.button?.image = StatusItemRenderer.image(
            cpuHistory: model.cpuHistory,
            memHistory: model.memHistory)
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.panelVisible = true
            model.refreshProcesses()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        for seconds in [0.5, 1.0, 2.0, 5.0] {
            let item = NSMenuItem(title: String(format: "Refresh every %.1fs", seconds),
                                  action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = model.interval == seconds ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        if !LoginItem.isInstalled {
            login.isEnabled = false
            login.toolTip = "Run `make install NAV=Pulse` first — a login item must not "
                + "point into .build, which `make clean` deletes."
        }
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // popUp avoids assigning statusItem.menu, which would hijack left-click.
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    @objc private func toggleLoginItem() {
        do {
            try LoginItem.toggle()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not change the login item"
            alert.informativeText = "\(error.localizedDescription)\n\nStatus: "
                + LoginItem.describe(LoginItem.status)
            alert.runModal()
            return
        }
        if LoginItem.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        model.setInterval(seconds)
    }

    func popoverDidClose(_ notification: Notification) {
        model.panelVisible = false
    }
}

let args = CommandLine.arguments
if args.contains("--dump") {
    Dump.run()
} else if let i = args.firstIndex(of: "--glyph"), i + 1 < args.count {
    Dump.glyph(to: args[i + 1])
} else if let i = args.firstIndex(of: "--panel"), i + 1 < args.count {
    Dump.panel(to: args[i + 1])
} else if let i = args.firstIndex(of: "--login") {
    LoginItem.runCLI(i + 1 < args.count ? args[i + 1] : "status")
} else if args.contains("--probe") {
    let app = NSApplication.shared
    let delegate = ProbeDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
