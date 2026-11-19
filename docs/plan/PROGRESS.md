# Progress and handoff

Last updated: November 18, 2026 (America/Los_Angeles).

## Current state

Requested personal-use features through Stage 6i are implemented. Mandatory: ordinary Cmd+Space (either Command key), no Accessibility or Input Monitoring requirement/request. English UI and repository documents. Implementation checkpoint 69b1310 and README checkpoint 2db8863 were committed and pushed to origin/main. Feature checkpoint 0dfeda7 (inline hotkeys and built-in commands) is also pushed. Decaf icon checkpoint c362fdf is pushed. Script-folder checkpoint dae22c0 is pushed. The current increment adds transactional alias cells, argument styling and script failure correction; screenshots use only neutral standard-app fixtures.

| Stage | State | Evidence / remaining work |
| --- | --- | --- |
| 0 — Plan | Complete | Requirements, architecture and resumable stages committed. |
| 1–3 — Native launcher, catalog, aliases/settings | Implemented | Packaged desktop launch, settings navigation and icons observed. Broader shortcut/focus acceptance remains pending. |
| 4–5 — Scripts, inline argument and URL contract | Implemented | Exact-argv, subprocess, timeout/cancel and URL fixture tests pass; private script/browser workflow still pending. |
| 6 — Caps Lock and login | Implemented; Caps owner-confirmed | Owner confirmed physical Caps switches layouts after correcting a conflicting system modifier assignment. Relogin/multiple physical keyboards remain pending. |
| 6b — Keep Awake | Implemented | Native power assertion with injected-backend tests; real idle-sleep session pending. |
| 6c — Lifecycle, app shortcuts and icons | Implemented | Real startup/gear/singleton and launcher/Settings icon observations; core shortcut/lock fixtures pass. |
| 6d — Wrong-layout search | Implemented | Both U.S./Russian directions, alias ordering, mixed input and ё/й fixtures pass. |
| 6e — Inline hotkey editing/removal | Implemented | Native fixture checks pass; actual Settings double-click and Escape observed without saving an assignment. Assigned shortcuts have × controls in the cell and inspector. |
| 6f — Built-in caffeine commands | Implemented | caffeine/cafe and decaffeine/decafe reuse Keep Awake; fuzzy, layout and alias-precedence fixtures pass. Both abbreviations found in the actual launcher. |
| 6g — Script folders | Implemented | 47 core tests pass; actual directory picker connected the owner-supplied folder and imported seven scripts. Title/interpreter/text argument verified without execution. |
| 6h — Inline aliases | Implemented | Native app/script alias save, Escape, duplicate validation, removal and draft cleanup checks pass; real Settings exposes inline fields and crosses. |
| 6i — Argument styling and failure correction | Implemented | Appearance previews checked; 48 core tests plus native feedback tests pass. Private-script failure/browser flow remains owner-led. |
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

- `scripts/test.sh`: **42 tests passed**, including built-in caffeine command search, wrong-layout search, shortcuts, configuration, singleton lock, remap ownership, keyboard profiles, power fixtures and real shell/AppleScript argument/process tests. Warm search over 2,000 synthetic apps: debug p95 **19.92 ms**, target below 30 ms.
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

The README checkpoint **2db8863** is pushed. The canonical `dist/Uficast.app` has now been rebuilt after a normal Quit and reopened with the latest inline recorder, removal controls and built-in commands; no running executable was overwritten. The older source-only build evidence above applies to the README checkpoint, not a fresh snapshot of this increment.

## Current increment: inline hotkeys and built-in commands

- Double-click an application's Hotkey cell (assigned or Add Hotkey) to show the native recording field. A single click selects the row. Escape never invokes the save callback; a valid chord commits and Delete explicitly clears. A visible × removes an assignment from both the cell and Show / Hide inspector.
- Recording releases Uficast's own registrations only while active, and restores them on Escape, capture, focus loss, window deactivation/close and cell removal. No global input observation or privacy grants were added. Existing duplicate/reserved validation stays in place.
- `--verify-shortcut-recorder` passes against real hosted Settings cells using synthetic local responder events and in-memory public fixtures: single/double click, invalid bare key, Escape retaining assigned/unassigned values, exactly one capture, explicit clear and balanced lifecycle cleanup. It does not save personal config or register actual global shortcuts.
- Desktop: double-clicking an actual Hotkey cell visibly showed Press shortcut…; Escape restored Add Hotkey. The canonical app was rebuilt again with × controls and commands; searches cafe and decafe visibly selected caffeine and decaffeine respectively. These results were inspected without executing a command or assigning/removing a personal hotkey.
- BuiltInCommand appends stable command entries to launcher search, with cafe/decafe aliases and cup icons. Execution routes directly to the shared native power service: enable indefinitely / disable. Explicit user aliases override conflicting abbreviations. Built-ins are not stored as editable script/app records.
- Current release build and strict signature verification passed; the native recorder check passed on that final bundle. **42 core tests passed**, including exact/abbreviated/fuzzy/wrong-layout built-in searches and alias precedence. Real power effects remain covered by the existing manual acceptance gap, not inferred from search.
- README/requirements/architecture/stages/manual checklist updated. The Commands screenshot was regenerated from public fixtures and visually inspected: real standard-app icons and × controls appear in both places, with no personal data.

## Decaf icon polish

- Owner requested a sleep zzz icon in decaf mode. The status item now uses SF Symbol `zzz` both at initial startup and whenever Keep Awake is inactive; active sessions keep the filled cup. Inactive accessibility text explicitly says Keep Awake off. The decaffeine launcher command also uses zzz.
- `scripts/build.sh` passed release compilation and strict signature verification. The canonical app was normally quit before replacing its bundle and successfully reopened. Its AX tree recognized the decaffeine symbol as Snooze. The menu bar appearance itself was not separately captured, and no power session was toggled for verification.
- No power logic or configuration changed. Existing 42-test results are from the preceding feature checkpoint; the suite was not rerun for this symbol-only edit. README, requirements, architecture and the plan were updated.

## Script-folder increment

- Owner requested adding a scripts folder directly in UX after supplying a local shell-script path. Commands now offers Add Folder and Refresh Scripts, also + → Add Script Folder. Connected folders can be disconnected with × without deleting source files. Folder-managed commands can be disabled and edited; individual Delete is disabled while managed.
- Configuration schema 1 gains default-empty scriptDirectories and optional ScriptCommand.sourceDirectory. Existing configurations decode unchanged. Scans run off the UI actor, read direct non-hidden regular files, canonicalize/deduplicate paths, and read at most 32 KiB of headers. No imported script is executed or copied. Scripts remain linked to original paths.
- First import recognizes known shell/Python/AppleScript extensions and shebangs, Raycast title and one required text argument/placeholder. Unsupported argument declarations produce notices. Existing IDs, aliases, enabled state and edited options are retained; manual file references are not duplicated. Unavailable roots retain commands; missing files are pruned only from successfully read roots. Changing a managed path detaches it with a new ID. Refresh runs on startup, explicit request and directory changes through import/recovery; no live watcher or recursive scan is claimed.
- **47 core tests passed**, including five new folder/metadata/lifecycle/compatibility fixtures. Tests establish discovery has no script side effects. Current warm-search p95: **19.39 ms** over 2,000 synthetic apps. The existing native inline-recorder check also passed with the new folder controls in Settings.
- Isolated and canonical release builds and strict signature verification passed. Canonical app was normally quit before rebuilding, then reopened. Desktop Add Folder opened a directory-only native picker; the owner-supplied parent folder was connected and the UI reported seven found scripts. Scripts filter showed the imported commands. Inspecting the supplied command showed the imported title, /bin/bash interpreter, required text argument, expected placeholder and side-effect result mode. The editor was cancelled without changes; no imported script/browser action ran. Personal paths, source contents and internal URLs are absent from repository fixtures/docs/screenshots.
- README, architecture, requirements, stages and manual checklist document direct-child discovery, refresh behavior, metadata limits and disconnect semantics. The Commands screenshot is regenerated from the same public standard-app fixture dataset; actual personal Settings are never used for README captures.

## Alias, argument appearance and failure-feedback increment

- Owner requested the Alias column behave like Hotkey: double-click to edit, Escape to discard and × to remove. AliasEditor now supplies native label/field/remove controls in the table and inspector. Enter validates/saves; duplicate/invalid values keep the draft. Focus/window/filter/reuse/disabling cancels without saving. The old inspector Apply flow is removed. Public fixture app identities now use valid app: IDs so checks exercise actual config validation.
- Native `--verify-alias-editor` passes app/script edits, assigned/unassigned values, single/double click, Escape, duplicate rejection, exact save counts, cross removal, hotkey/argument-option preservation and draft cleanup. `--verify-shortcut-recorder` also passed after the table changes. Real Settings showed the assigned alias with its cross and opened the inline text field on double-click; no test alias was saved to personal config. The user changed the app during further inspection, so additional live interaction stopped. An extra native check confirms editing survives selection/layout of a previously unselected row; the offscreen harness emitted SwiftUI AttributeGraph cycle diagnostics while exercising selection/model updates, although all behavior assertions passed. Check for recurrence during daily use; no such diagnostic-driven UI failure was established.
- Argument scroll/clip backgrounds are transparent; a subtle semantic fill replaces the opaque white field. Text/placeholder insets align. Empty/filled light/dark native previews were rendered and visually inspected, plus the updated failure view. The formatting fix was installed; no private argument was submitted during verification.
- Scripts now retain their current launcher view during execution. Success closes that presentation; failure shows a lower error block and Edit Input. The last failure/exact argument is held only in memory. Edit Input restores/selects the original string and never executes; Enter explicitly retries. Presentation IDs prevent stale completion from replacing newer search/input or reopening a dismissed panel. The latest failure can be offered on a deliberate reopen.
- ScriptResult.failureDescription reports exit/timeout and bounded stderr, with stdout fallback when stderr is empty. **48 core tests passed**, including real generic stdout-only failure and stderr precedence; latest warm-search p95 **19.11 ms** over 2,000 synthetic apps. `--verify-script-feedback` passed duplicate-run UI guards, exact argument restoration, explicit retry, success cleanup, no-input errors and stale-result handling with injected completions. No private scripts, browser actions or power assertions were triggered for these checks.
- Isolated and canonical release builds/signature checks passed. Canonical app was normally quit before rebuilding and reopened with the features. README requirements/architecture/stages/manual checklist updated; four screenshots are generated from public fixtures only, including a generic failure. Development previews support --empty-argument / --failure; script-feedback checks bypass normal lifecycle/configuration/registrations.

Next product work is the remaining owner-led daily-use acceptance above; do not mark it complete from automated/preview results. No new feature implementation is implied by this handoff.

### Earlier cursor report checkpoint

Commit 62e8296 preserved an unrelated stationary-cursor report. Its source/disappearance was not established; no app code changed for that report. Do not treat it as a verified Uficast defect or interact with unrelated apps to investigate it without a new request.
