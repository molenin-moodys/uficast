# Progress and handoff

Last updated: November 18, 2026 (America/Los_Angeles).

## Current state

The owner requested autonomous implementation while context permits. Native scaffold, app catalog and ranked search are implemented and release-built. **Mandatory steering: ordinary Cmd+Space, with no Accessibility or Input Monitoring requirement/request.** The earlier right-only event tap has been removed. Real desktop shortcut delivery remains pending manual acceptance; continue independent catalog/settings work without claiming that check passed.

| Stage | State | Evidence / remaining work |
| --- | --- | --- |
| 0 — Plan | Complete | Initial planning commit a5021c5; updated by subsequent steering. |
| 1 — Native app and global shortcut | Implemented; manual acceptance pending | SwiftPM/AppKit app, Carbon registration, menu/Edit actions, panel and settings scaffold. Real shortcut delivery/focus still pending. |
| 2 — Application catalog/search | Implemented; desktop acceptance pending | Catalog fixtures and ranking tests pass; actual app activation and UI still require desktop checks. |
| 3 — Settings/persistence/aliases | Not started | Depends on models/catalog. |
| 4 — Script runner | Not started | Depends on persistence/settings. |
| 5 — Inline argument/URL workflow | Not started | Depends on runner/panel. |
| 6 — Caps Lock/login lifecycle | Not started | Depends on lifecycle/settings. |
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

## Next action

Implement Stage 3: versioned configuration with atomic persistence/backup and validation, real Commands settings for aliases/enabled state, application roots, add-app and import/export. Preserve the no-Accessibility requirement and pending desktop checks.

## Remaining evidence gaps

Actual GUI launch and delivery of Cmd+Space, repeat/release behavior, Spotlight/Raycast coexistence, standard editing/focus, fullscreen/two monitors, sleep/wake/Secure Input; Automation consent/signing behavior; owner's real Kibana script/environment; F19 remapping and perceived switching latency. Use generic scripts and fixture mappings until actual tests are authorized through normal user actions.

At every checkpoint update actual checks/results, stage states, and the next concrete action, then commit relevant files. Use Git history for the latest checkpoint hash.
