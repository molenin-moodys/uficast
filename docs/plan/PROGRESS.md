# Progress and handoff

Last updated: November 18, 2026 (America/Los_Angeles).

## Current state

The owner requested autonomous implementation while context permits. Native scaffold, app catalog and ranked search are implemented and release-built. **Mandatory steering: ordinary Cmd+Space, with no Accessibility or Input Monitoring requirement/request.** The earlier right-only event tap has been removed. Real desktop shortcut delivery remains pending manual acceptance; continue independent catalog/settings work without claiming that check passed.

| Stage | State | Evidence / remaining work |
| --- | --- | --- |
| 0 — Plan | Complete | Initial planning commit a5021c5; updated by subsequent steering. |
| 1 — Native app and global shortcut | Implemented; manual acceptance pending | SwiftPM/AppKit app, Carbon registration, menu/Edit actions, panel and settings scaffold. Real shortcut delivery/focus still pending. |
| 2 — Application catalog/search | Implemented; desktop acceptance pending | Catalog fixtures and ranking tests pass; actual app activation and UI still require desktop checks. |
| 3 — Settings/persistence/aliases | Implemented; desktop acceptance pending | 11 tests pass; release builds. Manual UI/restart flow remains pending. |
| 4 — Script runner | Implemented; app-controlled Automation checks pending | Native process-group runner, editor, run/cancel/history, shell and AppleScript fixtures pass. |
| 5 — Inline argument/URL workflow | Implemented; desktop workflow pending | Native NSTextView input and explicit URL mode; 22 tests pass and offscreen previews inspected. |
| 6 — Caps Lock/login lifecycle | Implemented; real system acceptance pending | 28 tests pass; real mapping/login items were not changed. |
| 7 — Daily-use validation/handoff | Not started | Requires actual desktop acceptance. |

## Environment and implemented paths

- macOS 26.6.2 (25G83), arm64, Swift 6.2.3, Command Line Tools; no full Xcode dependency or remote packages.
- Package.swift, Resources/Info.plist, scripts/build.sh and test.sh, Sources/UficastCore and Sources/Uficast, Tests/UficastCoreTests.
- App menu includes Open Launcher, Settings, registration status, Retry and Quit. Standard Edit actions support ordinary text editing. Panel is a nonactivating key-capable NSPanel.
- HotkeyService uses Carbon RegisterEventHotKey/pressed/released events, exclusive conflicts and repeat debouncing. No keyboard event tap or privacy preflight/request calls remain.
- --diagnostics reports bundle identity and the no-Accessibility design without registering a shortcut.
- Command Line Tools contains Testing.framework but SwiftPM needs an explicit framework path/rpath. test.sh handles that and disables unavailable XCTest.

## Evidence and pending checks

- The initial right-only scaffold built/tests passed, then was superseded before commit by the owner's no-Accessibility steering. Current Carbon implementation: scripts/test.sh passed both lifecycle tests; scripts/build.sh passed release build and strict signing verification; plutil lint passed; --diagnostics reports the expected bundle and requiresAccessibility=false.
- The initial packaged diagnostics reported the correct bundle identity and no existing keyboard permissions. These calls have since been removed; app diagnostics no longer query privacy state.
- Desktop launch through Computer Use timed out twice; the app did not appear in that inventory. Its optional launch API was unavailable. **No successful GUI launch or visual/focus/paste/shortcut test is claimed.** This does not establish the cause of the launch failure.
- No Accessibility/Input Monitoring grants, Spotlight/Raycast settings, keyboard mappings, or login items were changed by the agent.
- Matching Spotlight/Raycast chords must be released by the owner. Carbon success alone cannot prove freedom from system shortcut interference.

## Stage 2 validation

- Seven tests pass: hotkey lifecycle, alias precedence even against heavy usage, rank tiers, fuzzy abbreviation, diacritic/case normalization, disabled entries, stable ties/limits, and catalog fixtures with duplicate bundles/nested helpers.
- Debug warm search over 2,000 synthetic apps and four queries: p95 10.81 ms over 40 samples (target below 30 ms).
- Release app builds and strict signature verification passes. Read-only --catalog-summary found 101 applications, zero unavailable default roots, discovery 0.240 seconds. No apps were launched by this command.
- CatalogService discovers off the UI actor, retains existing results during refresh, watches root directory changes, and refreshes stale data on opening/manual request. Icons are loaded off the UI actor and transferred as Data.
- Launcher now renders search results with icons/types/aliases, selection and Enter/double-click activation. NSWorkspace activation and focus behavior remain unverified manually.
- CLT lacks the optional _Testing_Foundation Swift module despite shipping its binary. test.sh disables automatic cross-import overlays only for that incomplete CLT setup; generic Testing assertions pass.

## Stage 3 validation

- ConfigStore actor uses versioned/validated JSON, atomic writes, private directory/file permissions, first-save backup, last-known-good backup on subsequent saves, and explicit backup restoration with preservation of the replaced original.
- Tests cover app/script alias conflicts, disabled alias reuse, round trips, missing app fallback records, corrupt-file save protection, backup recovery and unsupported future versions during load/save/recovery.
- Settings now has General/Commands navigation, searchable All/Apps/Scripts table, selection/alias inspector, Enabled checkboxes, application folders/add-app, import/export/recovery. Normal startup loads config without writing defaults; errors preserve the file and disable edits.
- All 11 tests passed after final Stage 3 changes; latest debug search p95 9.85 ms. Release build and strict signature verification passed. UI interaction/restart testing is still pending.
- Catalog root-change notifications are now debounced. Paths are preserved on import; missing files are not silently remapped.

## Stages 4–5 validation

- Script CRUD/editor supports interpreter/path, alias/enabled state, one required argument, placeholder, result mode, timeout, working directory and JSON environment overrides. Delete removes the config record, not the source file.
- Runner uses a small C posix_spawn worker, not Foundation Process: each run owns a process group, stdin is /dev/null, pipes are polled/drained concurrently with 1 MiB capture per stream, cancellation/deadline sends TERM then KILL, and the child leader stays waitable until cleanup to prevent PID reuse. Deliberately detached daemons are outside the cleanup contract.
- 22 tests passed: unchanged Unicode/quotes/metacharacters/newlines as one argv element, zero args, cwd/environment, missing/non-executable files, concurrent large pipes, nonzero exit, uncooperative shell+child timeout, exited leader with child-held pipes, cancellation, duplicate protection, argument rejection before spawn, plain AppleScript echo and strict URL outputs.
- Latest debug search p95 10.38 ms. Release build/strict signature check passed; clang static analysis (-Wall/-Wextra) reported no issues in the C worker. Source scan finds no AX/CGEvent keyboard-tap or grant APIs.
- Inline argument mode is wired to Tab/Enter, ordinary paste/edit/undo, Escape/empty Backspace and one unchanged string. NSTextView avoids single-line field newline normalization. Async failures appear in bounded in-memory recent runs; stdout/URLs/arguments/environment are not persisted. Normal quit cancels managed runs and waits for cleanup.
- Search query changes now select the top-ranked match rather than retaining an older matching selection that could hide an exact alias.
- Offscreen native launcher, argument and Settings PNGs were rendered and visually inspected under .build/previews. Fixed token sizing and hosted control/background rendering. These are deterministic fixture previews with no hotkey registration or grants, and do not establish real keyboard/paste/focus/browser behavior.
- Read-only hidutil property --get UserKeyMapping returned (null). No mapping was applied.

## Stage 6 validation

- Caps Lock → F19 uses hidutil through the bounded native utility runner. Ownership is recorded atomically before a write; unrelated entries survive, existing identical mappings stay externally owned, competing Caps Lock maps are rejected, and disable/quit restores only a still-owned entry. Failed verification retains recovery state.
- Registry-only IOKit device lifecycle notifications and wake events trigger reconciliation. No HID devices are opened and no keyboard input is observed.
- Preferences default off, including legacy schema-1 decoding. Settings exposes the explicit toggle, current-map read and F19/system shortcut guidance. Native SMAppService provides optional start-at-login with actual enabled/pending/disabled status.
- 28 tests pass, including remapping ownership/restart/failure fixtures and literal utility argv. Release build/signing passed. Actual hidutil writes, input-source latency, device reconnect and login-item registration remain untested by design.
- Offscreen General, script editor and dark argument previews generated. Script-editor header/footer background needs the same explicit root background as Settings (transparent offscreen regions); real desktop remains pending.

## Next action

Owner added a built-in Caffeine / Keep Awake feature. Implement Stage 6b with native IOPM assertions (no Accessibility or caffeinate subprocess), explicit menu toggle and optional session duration, default off and no automatic restore across app launches. Test with an injected fake assertion backend. Then finish clean-source build and Stage 7 handoff.

## Remaining evidence gaps

### Cursor report checkpoint (November 18)

- Owner reported a stationary cursor and suspects ChatGPT's pointer. Computer Use inventory did not list Uficast; direct inspection of the ChatGPT app was unavailable. The cursor's source and disappearance remain unverified. Ended the Computer Use check without interacting with other apps or changing system settings.
- Preserved the existing uncommitted implementation work. No app code changed or build/tests ran for this report. Next project step remains Stage 6b, beginning with review of the existing working-tree changes before further implementation.

Actual GUI launch and delivery of Cmd+Space, repeat/release behavior, Spotlight/Raycast coexistence, standard editing/focus, fullscreen/two monitors, sleep/wake/Secure Input; Automation consent/signing behavior; owner's real Kibana script/environment; F19 remapping and perceived switching latency. Use generic scripts and fixture mappings until actual tests are authorized through normal user actions.

At every checkpoint update actual checks/results, stage states, and the next concrete action, then commit relevant files. Use Git history for the latest checkpoint hash.
