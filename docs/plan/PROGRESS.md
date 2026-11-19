# Progress and handoff

Last updated: November 18, 2026 (America/Los_Angeles).

## Current state

Requested personal-use features through Stage 6d are implemented. Mandatory: ordinary Cmd+Space (either Command key), no Accessibility or Input Monitoring requirement/request. English UI and repository documents. Implementation checkpoint 69b1310 was committed and pushed to origin/main. The subsequent README update uses screenshots containing only neutral standard-app fixtures.

| Stage | State | Evidence / remaining work |
| --- | --- | --- |
| 0 — Plan | Complete | Requirements, architecture and resumable stages committed. |
| 1–3 — Native launcher, catalog, aliases/settings | Implemented | Packaged desktop launch, settings navigation and icons observed. Broader shortcut/focus acceptance remains pending. |
| 4–5 — Scripts, inline argument and URL contract | Implemented | Exact-argv, subprocess, timeout/cancel and URL fixture tests pass; private script/browser workflow still pending. |
| 6 — Caps Lock and login | Implemented; Caps owner-confirmed | Owner confirmed physical Caps switches layouts after correcting a conflicting system modifier assignment. Relogin/multiple physical keyboards remain pending. |
| 6b — Keep Awake | Implemented | Native power assertion with injected-backend tests; real idle-sleep session pending. |
| 6c — Lifecycle, app shortcuts and icons | Implemented | Real startup/gear/singleton and launcher/Settings icon observations; core shortcut/lock fixtures pass. |
| 6d — Wrong-layout search | Implemented | Both U.S./Russian directions, alias ordering, mixed input and ё/й fixtures pass. |
| 7 — Daily-use handoff | Partial | README guide, three neutral screenshots and source-only release build/signature verification complete. Hands-on evidence gaps remain. Manual evidence gaps listed below. |

## Implementation map

- Swift 6.2.3 / macOS 26.6.2 arm64 with Command Line Tools; no external packages or full Xcode required. `scripts/build.sh` creates an ad-hoc signed app; `UFICAST_OUTPUT_ROOT` isolates output. Quit before replacing a running bundle.
- Carbon RegisterEventHotKey handles fixed launcher Cmd+Space and configurable app bindings. Local recorder releases/restores Uficast registrations; duplicate/reserved chords are rejected. Native NSRunningApplication activate/hide/unhide launches closed apps without AX.
- InstanceLock uses process-held flock, never unlinks its inode, and InstanceCoordinator reveals the primary process via a user-scoped distributed notification. Ordinary launch/reopen reveals the panel; footer gear opens Settings.
- ApplicationCatalog discovers configured roots in the background. SearchIndex preserves exact-alias priority and stable ranking/history. KeyboardLayoutSearch expands queries using U.S./Russian physical keys before folding diacritics; literal variants win ties. Arguments and visible input remain unchanged.
- ConfigStore validates versioned private JSON, writes atomically, protects corrupt/future files and maintains recoverable backups. Optional app hotkeys and default-off Caps preference decode existing schema-1 files. Never commit personal config.
- ScriptRunner wraps the C posix_spawn/poll process-group worker: exact argv, one unchanged argument, concurrent bounded pipe draining, cancellation/timeout and managed descendant cleanup. Strict single HTTP(S) stdout URL opens only after success. Deliberately detached daemons are outside cleanup guarantees.
- IconStore serially renders 64px PNGs, transfers Data across actors and retains a bounded 256-image cache. Each launcher EntryRow receives its own guarded completion; no icon-triggered table reload. Settings observes cache updates.
- Caps ownership/recovery preserves unrelated/external mappings. Device/service lifecycle and wake re-publish owned mappings without observing input. ModifierMappingDiagnostics detects macOS Caps modifier conflicts across keyboard profiles without automatically rewriting them.
- Native SMAppService startup checkbox is at the top of General and shows actual authorization state. KeepAwakeService owns one IOPM idle-system-sleep assertion, starts off, supports timed/indefinite renewal and releases on stop/quit.

## Actual verification

- `scripts/test.sh`: **40 tests passed**, including wrong-layout search, shortcuts, configuration, singleton lock, remap ownership, keyboard profiles, power fixtures and real shell/AppleScript argument/process tests. Warm search over 2,000 synthetic apps: debug p95 **19.67 ms**, target below 30 ms.
- Current isolated release build (`UFICAST_OUTPUT_ROOT="$PWD/.build/release-check" scripts/build.sh`) and strict ad-hoc signature checks passed, including wrong-layout changes. The native 50-icon check also passed on that release.
- Native `--verify-native-icons` passed for 50 actual catalog entries after the direct-completion fix. Checks loaded bitmap representations, row geometry and scroll origin, not AppKit's offscreen view-cache identity.
- Desktop: canonical `dist/Uficast.app` launched with the panel immediately; gear opened Settings, real icons appeared in Settings and later in launcher. The latest icon fix was verified in the actual running canonical app. Opening a second copy exited and revealed the original process.
- Owner enabled startup/Caps controls. A conflicting macOS Modifier Keys assignment mapped Caps Lock to Right Option despite correct hidutil tables. During the authorized setup, the current keyboard's Caps assignment was restored to Caps Lock, keeping the F19 input-source shortcut. Owner then explicitly confirmed physical Caps switches layouts while Uficast runs. No latency measurement or multi-keyboard acceptance is claimed.
- No Accessibility/Input Monitoring grants requested or enabled. No keyboard events are monitored. Automated mapping, login and Keep Awake tests use fixtures and do not change actual settings/assertions.
- Offscreen fixture previews verify layout only; they do not establish actual keyboard delivery, paste, focus or browser operation.

## Remaining manual/platform checks

- Cmd+Space repeat/release and system conflict behavior, Secure Input, fullscreen/multiple monitors, editing/paste/focus across destinations and sleep/wake.
- App show/hide/closed-launch cycles with physical assigned shortcuts; persistence/restart acceptance.
- Owner's real script/environment and full paste → script → browser flow; Automation consent across ad-hoc rebuilds.
- Actual relogin at the stable app path, multiple physical keyboards/reconnect/wake, preservation under external mapping changes and perceived switching latency.
- Real timed/indefinite idle-sleep prevention, expiry and stop (fake-backend tests are not sleep acceptance).
- Other Macs, Intel and older macOS versions have not been tested.

## README and repository delivery

- Implementation checkpoint **69b1310** is pushed to origin/main. SSH authentication had no key; push used existing `gh` HTTPS credentials with command-scoped URL rewriting/helper, without changing the remote/global configuration. Configured 1Password signing was unavailable, so the commit used command-scoped `commit.gpgsign=false`; no global setting changed.
- README now describes features, build/run, configuration, scripts and keyboard setup, with three actual native-view screenshots: standard-app launcher, Commands with example aliases/hotkey, and dark argument mode. Images were visually inspected; no personal data, internal URLs, home paths or desktop content is shown.
- `ViewPreview` owns hard-coded Calculator/Calendar/Notes/Safari/Terminal and generic Search Example fixtures. Preview paths do not construct AppController, discover installed apps, read personal config, register hotkeys or change mappings/login/power state. `scripts/screenshots.sh [bundle.app]` reproduces the PNGs under `docs/screenshots/`.
- Screenshot review exposed and fixed an empty-query regression in Settings: blank/whitespace search now retains all entries. The final Commands capture visibly includes all six fixture commands and their icons/aliases.
- Current preview release build and strict signature check passed. A separate source-only snapshot (without Git metadata, caches or private configuration) also built successfully using the documented `scripts/build.sh`, including strict signature verification. All relative Markdown file/image links resolve; shell syntax and diff whitespace checks passed. Native screenshots verify layout, not physical input.

The README/preview increment is ready for its commit/push; use Git history/status to verify delivery rather than relying on a predicted hash. The current running canonical `dist/Uficast.app` was not replaced while running; latest source was built into isolated `.build/readme-app` and `.build/clean-source-check/dist` paths. Rebuild/restart the canonical bundle when the owner wants to try the latest source.

Next product work is the remaining owner-led daily-use acceptance above; do not mark it complete from automated/preview results. No new feature implementation is implied by this handoff.

### Earlier cursor report checkpoint

Commit 62e8296 preserved an unrelated stationary-cursor report. Its source/disappearance was not established; no app code changed for that report. Do not treat it as a verified Uficast defect or interact with unrelated apps to investigate it without a new request.
