# mantel

macOS menu bar apps. One shared `Makefile`, one directory per navbar under `navbars/`.
Every target takes `NAV=<name>`, default `Pulse`.

## Hard constraints

**No Xcode.** Command Line Tools + SwiftPM only, by explicit choice. `xcodebuild`,
`actool` and `ibtool` are unavailable — they're `/usr/bin` shims that error out
without a full Xcode. So: no `.xcodeproj`, no storyboards or xibs, no `.xcassets`.
Status icons are hand-rendered `NSImage` or SF Symbols; app icons use `iconutil`.

**Always sign with the `MyNavbarsLocalDev` identity, never ad-hoc.** Ad-hoc signing
makes the designated requirement a `cdhash`, which changes on every rebuild and
invalidates TCC grants (Accessibility, Input Monitoring, Screen Recording) and login
item registrations. The identity pins the cert leaf instead, which is stable. Verify
with `make dr` — the output must not contain `cdhash`. The identity keeps its
original name deliberately; renaming it mints a new cert and breaks that stability.

**Deployment target is `platforms: [.macOS("26.0")]`.** The string form is required —
`.macOS(.v26)` does not exist in PackageDescription at `swift-tools-version:6.0` and
fails to build.

## Verifying UI without a screen

`screencapture` is TCC-blocked from a terminal here (`could not create image from
rect`), so never try to screenshot the menu bar. Render headlessly instead:

- `make glyph` → PNG of the menu bar icon across four load levels
- `make panel` → PNG of the panel in **both** colour schemes (catches light-mode bugs)
- `Pulse --probe [minY|maxY|minX|maxX]` → prints popover and screen geometry

Then `Read` the PNG. This is how the panel-overflow and legend-wrapping bugs were
found; guessing at layout does not work.

## Swift 6 gotchas hit in this repo

- Strict concurrency is on. Anything touching AppKit statics needs `@MainActor`;
  mark plain constants `nonisolated` so non-UI code can still read them.
- `vm_kernel_page_size` is a non-Sendable global and won't compile. Use
  `sysctlbyname("hw.pagesize")`.
- Importing SwiftUI alongside AppKit makes `.png` ambiguous — write
  `NSBitmapImageRep.FileType.png`. It also slows type inference enough that
  arithmetic-heavy closures need explicit `(i: Int) -> Double` annotations.
- A single-file `swiftc` invocation treats the file as top-level code, so `@main`
  needs `-parse-as-library`. SwiftPM handles this itself.

## Bundling and running

A `.app` bundle with `LSUIElement` is required for a stable bundle identity — TCC,
login items, and `Bundle.main` resources all depend on it. An unbundled binary does
run (as `BackgroundOnly`, no Dock icon) and is fine for quick iteration, but has
`bundleID=NULL`.

Login items must point at the `~/Applications` copy, never `.build` — `make clean`
would delete the target. `make login-on` installs first for this reason.

`.build` caches absolute paths, so **after moving or renaming the repo, `make clean`
is mandatory** or the build fails with a stale module-cache path error.

## Metrics correctness (Pulse)

- `used` is **`total - cached - free`**, matching Activity Monitor's "Memory Used".
  Do not "simplify" it to `app + wired + compressed` — that omits ~0.3–1 GB of kernel
  pages AM never itemises, which is why `other` is displayed. Cross-check with
  `vm_stat`; every field should agree to rounding.
- `ps` per-process CPU is summed across cores and legitimately exceeds 100%.
- `comm` from `ps` contains spaces (e.g. `Core Audio Driver (…)`), so parse the four
  numeric columns with `maxSplits: 4` and take the remainder as the name.
- The first CPU sample after init is a meaningless delta — discard it.

## Menu bar design

The status item is **template-rendered monochrome, no text and no colour**, sized to
sit alongside the system icons. Detail belongs in the panel, not the bar. Don't
reintroduce a coloured or red alert state in the menu bar; red is for critical memory
pressure inside the panel only. Keep numeric labels padded to a fixed width so the
item never changes size as values cross 10% or 100%.

## Adding a navbar

`navbars/<Name>/` with a `Package.swift` (executable target, `.macOS("26.0")`) and an
`Info.plist` setting `LSUIElement`. No Makefile changes — `make run NAV=<Name>`.
