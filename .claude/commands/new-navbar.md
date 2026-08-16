---
description: Scaffold a new navbar under navbars/ and verify it builds and launches
---

Create a new menu bar app named `$1` (ask for the name if `$1` is empty).

Read `CLAUDE.md` first — the constraints there are non-negotiable.

1. Create `navbars/$1/Package.swift`: `swift-tools-version:6.0`, `platforms:
   [.macOS("26.0")]` (string form — `.v26` does not exist and fails to build), a
   single `.executableTarget(name: "$1", path: "Sources/$1")`.
2. Create `navbars/$1/Info.plist` mirroring `navbars/Pulse/Info.plist`:
   `CFBundleExecutable` and `CFBundleName` set to `$1`, `CFBundleIdentifier`
   `dev.local.navbars.<lowercased $1>`, `LSUIElement` true, `LSMinimumSystemVersion`
   26.0, `NSHighResolutionCapable` true.
3. Create `Sources/$1/main.swift` with an `NSApplicationDelegate` that installs an
   `NSStatusItem` and a `.transient` `NSPopover`. Set
   `host.sizingOptions = [.preferredContentSize]` on the `NSHostingController` —
   without it the popover keeps a stale 320x320 content size, clipping the panel and
   pushing it off the top of the screen. Use `.accessory` activation policy.
4. Keep the status item glyph template-rendered and monochrome, sized like the system
   icons. No colour, no alert state.
5. Verify, in this order, and report actual output rather than assuming:
   - `make build NAV=$1`
   - `make glyph NAV=$1` and `make panel NAV=$1` if it has any UI, then `Read` the
     PNGs — do not try `screencapture`, it is TCC-blocked here
   - `make run NAV=$1`, then confirm the process is alive with `pgrep -lx $1`
   - `make dr NAV=$1` — the requirement must pin `certificate leaf`, not `cdhash`
6. Finally, add a short section for `$1` to `README.md`.
