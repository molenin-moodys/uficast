# Implementation plan

Implement stages in order. A stage is a reviewable unit and may span more than one session; do not force unfinished work into a single token budget. Every stage ends with working-tree review, appropriate validation, a progress update, and a commit. Record a checkpoint if interrupted midway.

## Stage 0 — Plan and durable context

**Deliverable:** requirements, architectural decisions, this plan, and a next-session handoff committed to Git.

**Complete when:** the owner's decisions and defaults are distinguishable; the next implementation action is explicit. No app implementation or system settings changes are part of this stage.

## Stage 1 — Buildable app and global-trigger spike

**Purpose:** prove the highest-risk platform behavior before building the full launcher.

Tasks:

- Create SwiftPM targets, minimal test setup, Info.plist, ignored build directories, and a reproducible `.app` packaging script.
- Add a menu bar entry with Open, Settings placeholder, Quit, and visible hotkey-permission status.
- Show a minimal input-capable NSPanel from the menu; include a real Edit menu.
- Prototype side-specific Right Command + Space interception and consumption, with recovery and repeat handling.
- Establish actual privacy grants and local signing/install behavior on macOS 26. Do not change existing shortcut assignments automatically.

Validation:

- Build/package with Command Line Tools and launch the bundle, not only the SwiftPM executable.
- Owner-assisted check: Right Command + Space opens/closes once per press; Left Command + Space retains its configured behavior; both Command keys and extra modifiers follow the documented policy.
- No leaked Space/repeat or stuck modifier when Command is released before Space. Repeat after sleep/wake and permission loss/regrant.
- The panel accepts Cmd+V and returns focus after Escape. Check normal and full-screen apps and two displays when available.

**Exit gate:** a recorded supported solution for the exact chord. If the tap conflicts with Spotlight, investigate here; do not silently replace it with generic Cmd+Space. Unavailable manual checks must be recorded as pending before proceeding past this gate.

Suggested commit: `feat: scaffold native app and right-command launcher trigger`.

## Stage 2 — Application catalog and fast search

Tasks:

- Add stable app/script item models and initial search engine.
- Discover configured application roots without listing nested helpers; deduplicate by identity and handle missing/moved apps.
- Render icon/name/type rows, selection, empty state, keyboard navigation, Enter launch/activate, outside-click dismissal, and screen placement.
- Implement deterministic exact/prefix/substring/fuzzy ranking with reserved top priority for exact aliases.
- Refresh the catalog asynchronously and load icons without blocking query changes.

Validation:

- Unit tests for rank tiers, fuzzy ordering, case normalization, exact-alias precedence, and stable tie-breaking.
- Launch a real app and activate an already running app. Check new/removed apps and manual Refresh.
- Measure warm search over a fixture catalog of 2,000 items; initial target p95 below 30 ms. Warm panel-show target below 100 ms on the development Mac. Record measured conditions; targets are not achieved until measured.

**Complete when:** it is a usable app launcher even before script support; discovery never blocks typing.

Suggested commit: `feat: add application discovery and ranked launcher search`.

## Stage 3 — Settings, persistence, and aliases

Tasks:

- Implement versioned ConfigStore with validation, atomic save, last-known-good backup, and recovery messages.
- Build General and Commands settings matching the reference structure: search, All/Apps/Scripts filters, table, Alias and Enabled editing, and add control.
- Persist app overrides separately from discovery; implement unique aliases across enabled entries and exact-alias selection.
- Add custom application roots and application paths, plus manual catalog Refresh.
- Support basic export/import with validation and explicit handling of machine-specific script/app paths; do not assume portability of absolute paths.

Validation:

- Round-trip configuration and restart the packaged app with aliases/enabled state intact.
- Test conflicting aliases, disabled records, missing app paths, corrupt JSON, and unsupported future schema without data loss.
- Compare light/dark Settings and launcher visually against the described screenshot hierarchy. Check tab order and standard editing shortcuts.

**Complete when:** the owner can configure and launch an application alias entirely through the UI.

Suggested commit: `feat: add raycast-inspired settings and persistent aliases`.

## Stage 4 — Local script runner

Tasks:

- Add script CRUD and editor fields: executable/interpreter, argument requirement/placeholder, result mode, timeout, working directory, environment.
- Implement shell, osascript, and executable/script invocation with exact argv and no input interpolation.
- Add asynchronous, bounded stdout/stderr handling, timeout/cancellation, duplicate-run protection, and useful error status.
- Add a bounded recent-run status view and generic example scripts, including an AppleScript using `on run argv` and a public fixture URL generator.
- Document PATH behavior and test Automation consent from the built bundle when an AppleScript controls another app.

Validation:

- Integration fixtures assert one unchanged argument containing spaces, quotes, Unicode, shell metacharacters, and newlines; verify the input has no shell side effects.
- Cover success, no argument, missing file/interpreter, permission denied, nonzero exit, excessive simultaneous stdout/stderr, and timeout with a spawned child.
- Verify no UI freeze while a script is running and no automatic opening of stdout in discard mode.

**Complete when:** script commands work through the runner and editor, with explicit result contracts ready for argument-mode integration.

Suggested commit: `feat: add configurable local script execution`.

## Stage 5 — Inline argument workflow and browser result

Tasks:

- Implement the explicit search/argument state transition and pinned command token/field layout.
- Support `k` → Tab → Cmd+V → Enter, Enter-to-enter-argument-mode, and Escape/empty-Backspace return behavior.
- Pass exactly one field value; validate required content without altering the submitted text.
- Add openURL result validation and NSWorkspace opening on successful exit only.
- Preserve useful error discoverability without stealing focus from the browser or reopening the panel.

Validation:

- Full packaged-app workflow using a generic Kibana-style command: alias `k`, placeholder `log_stream`, encoded test argument, default browser open.
- Confirm Cmd+V, select/copy/cut/undo, Unicode input, newlines, whitespace validation, and reopening the launcher.
- Test malformed URL, multiple URLs/lines, unsupported scheme, empty output, nonzero exit, timeout, and single-open behavior.
- Migrate the owner's real Kibana script only when its source is available; generic success does not prove that private script works.

**Complete when:** the central interaction from the first screenshot works end to end.

Suggested commit: `feat: add inline script arguments and URL results`.

## Stage 6 — Caps Lock remapping and login lifecycle

Tasks:

- Add a hidutil mapping adapter with read/merge/write behavior and an ownership/recovery record.
- Implement explicit enable/disable of Caps Lock → F19, preserving unrelated mappings and handling pre-existing identical/conflicting mappings.
- Reconcile owned mappings on startup and wake/device reconnect; handle normal quit and crash recovery without a separate daemon.
- Add Settings status, conflict explanations, and instructions for assigning F19 to the macOS input-source switching shortcut.
- Add optional start-at-login through SMAppService and report actual authorization status.

Validation:

- Test merge/restore/ownership logic with fixtures; test failures without mutating the real machine.
- During an explicit owner-approved setup/test, verify Caps Lock emits F19 and the configured system action switches the existing two layouts; compare perceived delay with the previous configuration.
- Test preservation of another mapping, external Caps Lock changes, enabling an already externally managed F19 mapping, restart, sleep/wake, keyboard reconnect, normal quit, and recovery after simulated crash.
- Validate actual relogin behavior with start-at-login enabled; report manual checks still pending.

**Complete when:** the owner has a working system shortcut and mapping lifecycle is understood and documented. A mapping-only test does not prove improved layout-switching latency.

Suggested commit: `feat: add caps-lock remapping and launch-at-login`.

## Stage 7 — Daily-use verification and source-build handoff

Tasks:

- Run a focused end-to-end pass across app launch, aliases, argument scripts, browser results, focus, remapping, and login lifecycle.
- Polish reference fidelity, spacing, icons, keyboard focus, light/dark appearance, and empty/error states based on actual screenshots.
- Verify all required permissions and rebuilding/installing behavior. Document known limitations, including Secure Input or privacy regrant if observed.
- Finish README with build/install/run instructions, configuration locations and backup, script examples, F19 setup/reversal, and troubleshooting.
- Record actual performance numbers and outstanding manual/platform limitations. Make sure private URLs/config and build output are ignored.

Validation:

- Build a release `.app` from a fresh source directory/check-out using only documented steps and available Command Line Tools.
- Run the targeted test suite and the end-to-end acceptance list in REQUIREMENTS; repeat checks only when subsequent changes justify it.
- Owner daily-use trial for opening apps and the real `k` workflow when its script is provided.

**Complete when:** all confirmed v1 requirements have evidence, remaining limitations are explicit, and another personal Mac can build from source using the README. Do not claim tests on another Mac or a reboot happened unless they did.

Suggested commit: `docs: finalize build guide and v1 validation` (include polish changes in a separate commit if substantial).

## Session boundary protocol

1. Read PROGRESS and inspect `git status`; preserve unrelated work.
2. Work on the next unfinished stage, respecting its dependencies and exit gate.
3. Run meaningful checks appropriate to changed behavior. Pure documentation edits need link/content/diff review, not application tests.
4. Update PROGRESS with stage state, implemented paths, commands and results, pending manual checks, blockers, and the next concrete action.
5. Record changed decisions in ARCHITECTURE/REQUIREMENTS and adjust later tasks if needed.
6. Review the diff and commit relevant files. A commit checkpoint is not evidence a stage passed validation.

Resume prompt for future sessions:

> Read AGENTS.md and docs/plan/PROGRESS.md, then continue the next unfinished stage of docs/plan/IMPLEMENTATION_PLAN.md. Follow the agreed requirements and architecture, update the handoff with actual verification results, and commit the completed increment.
