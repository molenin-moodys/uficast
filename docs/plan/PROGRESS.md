# Progress and handoff

Last updated: November 18, 2026 (America/Los_Angeles).

## Current state

The owner requested autonomous implementation while context permits. Stage 1 scaffold is implemented and release-built. **Mandatory steering: ordinary Cmd+Space, with no Accessibility or Input Monitoring requirement/request.** The earlier right-only event tap has been removed. Real desktop shortcut delivery remains pending manual acceptance; continue independent catalog/settings work without claiming that check passed.

| Stage | State | Evidence / remaining work |
| --- | --- | --- |
| 0 — Plan | Complete | Initial planning commit a5021c5; updated by subsequent steering. |
| 1 — Native app and global shortcut | Implemented; manual acceptance pending | SwiftPM/AppKit app, Carbon registration, menu/Edit actions, panel and settings scaffold. Real shortcut delivery/focus still pending. |
| 2 — Application catalog/search | Next | Can proceed with Stage 1 manual checks explicitly pending. |
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

## Next action

Implement Stage 2: stable app records, asynchronous discovery, deterministic alias-first/fuzzy ranking, result rows and app launch. Leave desktop acceptance explicitly pending.

## Remaining evidence gaps

Actual GUI launch and delivery of Cmd+Space, repeat/release behavior, Spotlight/Raycast coexistence, standard editing/focus, fullscreen/two monitors, sleep/wake/Secure Input; Automation consent/signing behavior; owner's real Kibana script/environment; F19 remapping and perceived switching latency. Use generic scripts and fixture mappings until actual tests are authorized through normal user actions.

At every checkpoint update actual checks/results, stage states, and the next concrete action, then commit relevant files. Use Git history for the latest checkpoint hash.
