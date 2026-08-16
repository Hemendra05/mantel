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

## Claude account data (Quota)

**Broker auth through the `claude` CLI. Never read the OAuth token.** Credentials live
in the macOS keychain under `Claude Code-credentials-<hash>`. Reading that item is
possible but was rejected on purpose:

- OAuth refresh tokens rotate. A second process that refreshes can invalidate the
  token Claude Code holds and silently sign the user out of their CLI.
- The item's ACL belongs to Claude Code, so another binary triggers a keychain
  prompt, and holding a long-lived token in a menu bar app is a real leak surface.

`claude auth status --json` returns `loggedIn`, `authMethod`, `apiProvider`, `email`,
`orgId`, `orgName`, `subscriptionType`. It costs ~200ms and spawns a process, so poll
on the order of minutes and on panel open — never on a one-second timer.

**Usage limits come from `claude -p "/usage"`, not from the API.** Full invocation:

```
claude -p "/usage" --max-turns 1 --output-format json --no-session-persistence
```

Three properties make this viable, each measured rather than assumed:

- **Costs no quota.** The JSON envelope reports `num_turns: 0`, `total_cost_usd: 0`
  and all token counts zero — `/usage` is a local command, so a quota monitor built
  on it does not consume the quota it reports. Two back-to-back runs returned
  identical percentages.
- **`--no-session-persistence` is mandatory.** Without it every poll leaves a
  transcript in `~/.claude/projects`; at a 10-minute interval that is ~144 stray
  session files a day. Verified: file count unchanged across polls.
- **~4s per call**, spawning a Node process. Free in quota, not in CPU — poll on the
  order of minutes, and publish the auth half first so the panel is never blank.

The limits text is in `.result` and is human-facing prose that varies by plan
(`Current session:`, `Current week (all models):`, and an Opus line on Max). Parse it
positionally and **skip anything unrecognised** — never guess a number. Rate-limit
records do appear in `~/.claude/projects/*.jsonl`, but only after a limit is hit, so
they are useless as a live gauge.

`https://api.anthropic.com/api/oauth/usage` exists (429 unauthenticated, not 404) and
would also work, but needs the OAuth token. The CLI route makes that unnecessary.

Two subprocess traps, both already handled in `ClaudeCLI.swift`: a `.app` launched
from Finder does not inherit your shell `PATH`, so resolve `claude` by absolute path;
and `ANTHROPIC_*` env vars are stripped so a stray key cannot redirect the query to a
different account.

## Login items

`LoginItem.swift` is duplicated per navbar and reads its name from `Bundle.main`, so
the copies are byte-identical on purpose — lift it into a shared package if a third
navbar needs it, rather than letting the copies drift.

Whenever a navbar gains `--login`, wire it into the `main.swift` argument switch
**before** the final `else`. A flag that falls through starts the full app and its
event loop, so `make login-on` hangs forever instead of registering anything.

## Adding a navbar

`navbars/<Name>/` with a `Package.swift` (executable target, `.macOS("26.0")`) and an
`Info.plist` setting `LSUIElement`. No Makefile changes — `make run NAV=<Name>`.
