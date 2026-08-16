# Changelog

Notable changes to mantel. Format follows [Keep a Changelog](https://keepachangelog.com);
this project does not use semantic versioning yet, so entries are grouped by date.

## [Unreleased]

### Security

- **History rewritten.** All seven commits were rewritten to purge
  `tools/devsign.crt` from every tree and to correct the author and committer
  email. Old commit SHAs are therefore invalid; anyone with an existing clone must
  re-clone rather than pull.
- The remote was then deleted and recreated to complete the purge. Verified against
  the new remote: the cert 404s at all eight commits, and every pre-rewrite SHA is
  gone.
- Note for future purges: **a force push alone does not remove the old objects from
  GitHub.** Measured here — after the rewrite and force push, the purged blob was
  still served at its pre-rewrite SHAs. Orphaned commits stay reachable by exact SHA
  until GitHub garbage-collects, which needs GitHub Support or a delete-and-recreate;
  `git gc --prune=now` only cleans the local clone. If a real secret is ever
  committed, **rotate it** — do not assume a rewrite removed it.
- When verifying a purge, check `gh api` **exit codes**, not output text: `gh` prints
  its error JSON to stdout, so a body containing `"status":"404"` matches a naive
  digit or content grep and reports a false positive. Include a control probe (a file
  that exists, one that never did) to prove the test discriminates at all.

### Changed

- **Quota polls at `.utility` QoS**, which cuts the instantaneous load of a usage
  poll from roughly 157% of a core to 66% for the same total work — the CPU spike
  every refresh. Measured: 4.32s wall / 6.78s CPU before, 10.8s wall / 7.13s CPU
  after. `.background` was tried and rejected; it doubles total CPU time (13.4s) by
  running everything on slower cores.
- Opening Quota's panel no longer re-spawns the CLI if the numbers are under three
  minutes old, so repeatedly opening it is free.
- Usage-call timeout raised 45s → 90s to match the longer wall time at lower QoS.

### Security

- `tools/devsign.crt` is no longer tracked in git. It is a machine-local artifact
  and meaningless to anyone else; `make-signing-cert.sh` now re-exports it from the
  keychain when absent, so a fresh clone still works. It contains no private key —
  the key has never left the login keychain.
- Permission rules in `.claude/settings.json` no longer hardcode an absolute home
  path, which leaked a username.

### Added

- This changelog.

## 2026-08-17

### Added

- **Quota navbar** — Claude account and quota: email, organization, plan tier, auth
  method, API provider, plus session and weekly usage with reset times. Menu bar
  shows two concentric arcs (outer session, inner week).
- Usage limits sourced from `claude -p "/usage"`. Verified to cost no quota
  (`num_turns: 0`, `total_cost_usd: 0`), so the monitor does not consume what it
  measures. Runs with `--no-session-persistence`, without which every poll leaves a
  transcript in `~/.claude/projects`.
- Launch-at-login for both navbars via `SMAppService`, with `make login-on/off/status`.
  Registration verified in the Background Task Management database.
- `CLAUDE.md`, project permission settings, and a `/new-navbar` command.

### Changed

- Renamed the project from `my-navbars` to **mantel**.
- Quota's menu bar glyph went from a single ring with a centre dot (which read as a
  record button and showed one number) to two concentric arcs carrying both limits.
- Quota's panel dropped nested cards for a flat hierarchy: usage leads, account
  demoted to a footer, reset times shortened by dropping the timezone parenthetical.

### Fixed

- `make login-on` hung forever for Quota: it had no `--login` handler, so the flag
  fell through the argument switch and started the app's event loop instead of
  registering anything.
- Permission rules that a semantic escape could widen (`Bash(make build *)` allows
  `-f other.mk`) replaced with exact commands; keychain secret reads denied outright.

### Security

- Auth is brokered through the `claude` CLI rather than by reading the OAuth token
  from the keychain. Refresh tokens rotate, so a second process that refreshed one
  could invalidate the token Claude Code holds and sign the user out of their CLI.
- `ANTHROPIC_*` is stripped from the CLI subprocess environment so a stray key
  cannot silently redirect a query to a different account.

## 2026-08-16

### Added

- Initial repo: shared `Makefile` driving every navbar via `NAV=<name>`, built with
  Command Line Tools and SwiftPM only — no Xcode.
- **Pulse navbar** — CPU and memory monitor. Menu bar shows a CPU sparkline over a
  memory meter; the panel adds per-core bars, load averages, core topology, a
  segmented memory breakdown with swap and pressure, and top processes by CPU and RSS.
- `tools/make-signing-cert.sh`, creating a trusted self-signed identity so the
  designated requirement pins the cert leaf instead of a per-build `cdhash`. Without
  it, every rebuild invalidates TCC grants and login items.
- Headless UI verification (`make glyph`, `make panel`, `--probe`), because
  `screencapture` is TCC-blocked from a terminal.

### Fixed

- Memory `used` corrected to `total - cached - free`, matching Activity Monitor.
  `app + wired + compressed` omits ~0.3–1 GB of kernel pages AM never itemises,
  which is why `other` is now shown explicitly.
- Popover was clipped and pushed 77pt above the top of the screen; the hosting
  controller needed `sizingOptions = [.preferredContentSize]`.
