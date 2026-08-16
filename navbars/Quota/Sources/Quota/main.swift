import AppKit
import ServiceManagement
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
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

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
        statusItem.button?.image = StatusItemRenderer.image(
            signedIn: model.status.loggedIn,
            session: model.usage.session?.fraction,
            week: model.usage.week?.fraction)
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        if !LoginItem.isInstalled {
            login.isEnabled = false
            login.toolTip = "Run `make install NAV=Quota` first — a login item must not "
                + "point into .build, which `make clean` deletes."
        }
        menu.addItem(login)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow),
                                 keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Quota", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        // popUp avoids assigning statusItem.menu, which would hijack left-click.
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func refreshNow() { model.refresh() }

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

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refreshIfStale()
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
} else if let i = args.firstIndex(of: "--login") {
    LoginItem.runCLI(i + 1 < args.count ? args[i + 1] : "status")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
