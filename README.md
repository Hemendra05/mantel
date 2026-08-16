# my-navbars

macOS menu bar apps built with Command Line Tools + SwiftPM only — no Xcode, no
`xcodebuild`, no asset catalogs. One shared `Makefile` drives every navbar.

## Prerequisites

Command Line Tools and a trusted local code-signing identity. Ad-hoc signing makes
the designated requirement a `cdhash`, which changes on every rebuild and invalidates
TCC grants (Accessibility, Input Monitoring, Screen Recording) plus login items. Run
once:

```sh
tools/make-signing-cert.sh
```

It generates a self-signed code-signing cert, trusts it (needs `sudo`), and proves the
requirement is stable by signing two different bundles and diffing `codesign -d -r-`.

## Usage

Every target takes `NAV=<name>` (default `Pulse`):

```sh
make run            # build, bundle, sign, launch
make stop
make install        # copy to ~/Applications
make login-on       # install + register as a login item
make login-off
make login-status
make dr             # print the designated requirement
make dump           # print one metrics snapshot as text
make glyph          # render the menu bar icon to /tmp/<NAV>-glyph.png
make panel          # render the panel, both colour schemes, to /tmp/<NAV>-panel.png
make clean
make list
```

`glyph` and `panel` exist because `screencapture` is TCC-blocked from a terminal, so UI
is reviewed by rendering it headlessly rather than by screenshotting the screen.

## Navbars

### Pulse

CPU and memory monitor. The menu bar shows a template-rendered CPU sparkline over a
memory meter — monochrome, no text, sized to match the system icons. Detail lives in
the panel: CPU sparkline, per-core bars, user/sys split, load averages, core topology;
memory as a segmented app/wired/compressed/other/cached bar with swap and pressure;
top five processes by CPU and by RSS.

Metrics come from `host_processor_info`, `host_statistics64` and `sysctl`, verified
against `vm_stat` and Activity Monitor. Note that `used` is
`total - cached - free`, which is how Activity Monitor computes "Memory Used" —
`app + wired + compressed` alone omits ~0.5–1 GB of kernel pages that AM never
itemises, which is why `other` is shown explicitly.

## Adding a navbar

Create `navbars/<Name>/` with a `Package.swift` (executable target, `platforms:
[.macOS("26.0")]`) and an `Info.plist` with `LSUIElement` set. No Makefile changes
needed — `make run NAV=<Name>`.
