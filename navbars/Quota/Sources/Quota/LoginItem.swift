import AppKit
import ServiceManagement

/// Wraps SMAppService.mainApp. Registration records the *running* bundle's path, so it
/// must be invoked from an installed copy — registering `.build` would pin the login
/// item to a path `make clean` deletes.
///
/// Kept identical across navbars (it reads its name from the bundle), so it can be
/// lifted into a shared package if a third navbar needs it.
@MainActor
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
    }

    static var isInstalled: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    static func enable() throws { try SMAppService.mainApp.register() }

    static func disable() throws { try SMAppService.mainApp.unregister() }

    static func toggle() throws {
        if isEnabled { try disable() } else { try enable() }
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        // mainApp reports notFound, not notRegistered, before its first register().
        case .notFound: "not registered (no record)"
        case .notRegistered: "not registered"
        case .enabled: "enabled"
        case .requiresApproval: "requires approval in System Settings > General > Login Items"
        @unknown default: "unknown (\(status.rawValue))"
        }
    }

    /// `<App> --login status|on|off`
    static func runCLI(_ command: String) {
        print("bundle    \(Bundle.main.bundlePath)")
        print("installed \(isInstalled)")
        switch command {
        case "status":
            break
        case "on":
            do { try enable() } catch { print("register failed: \(error)") }
        case "off":
            do { try disable() } catch { print("unregister failed: \(error)") }
        default:
            print("usage: \(appName) --login status|on|off")
            return
        }
        print("status    \(describe(status))")
    }
}
