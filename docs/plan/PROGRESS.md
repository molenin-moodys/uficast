# Progress and handoff

Last updated: November 18, 2026 (America/Los_Angeles).

## Current state

**Planning is complete. Application implementation has not started.** The owner's current request is to prepare and commit the English implementation plan. Do not interpret this planning checkpoint as authorization to apply keyboard mappings or change system shortcuts now.

| Stage | State | Evidence / remaining work |
| --- | --- | --- |
| 0 — Plan and durable context | Complete | README, AGENTS, requirements, architecture, staged implementation plan, and this handoff prepared and reviewed. Git history contains the planning checkpoint once committed. |
| 1 — Build and right-command spike | Not started | Highest-priority next implementation work. |
| 2 — Application catalog/search | Not started | Depends on Stage 1 chord gate. |
| 3 — Settings/persistence/aliases | Not started | Depends on models/catalog. |
| 4 — Script runner | Not started | Depends on persistence/settings. |
| 5 — Inline argument/URL workflow | Not started | Depends on runner and panel. |
| 6 — Caps Lock/login lifecycle | Not started | Depends on app lifecycle/settings. |
| 7 — Daily-use validation/handoff | Not started | Depends on preceding stages. |

## Confirmed environment

Read-only inspection on November 18, 2026:

- Repository: `/Users/ufian/pet/uficast`; initially empty, with an unborn `main` branch and no commits.
- macOS `26.6.2`, build `25G83`; `arm64`.
- Developer directory: `/Library/Developer/CommandLineTools`.
- Swift `6.2.3`; full Xcode has not been established as installed and must not be required initially.
- Installed SDK headers expose distinct right/left Command key codes and device flags.
- No application source, user scripts, real Kibana URL, or persisted config has been supplied.
- No hotkey, permission, remapping, browser, launch-at-login, or visual runtime checks have been performed.

## Decisions to preserve

- Native Swift + AppKit. Personal source builds. English product UI and documentation.
- Exact **Right Command + Space**, not generic Command + Space.
- UI configuration close to the Raycast settings screenshot; exact aliases beat fuzzy matches.
- One pasted text argument in the launcher. The `k`/Tab workflow is a first-class acceptance case.
- Shell/AppleScript/executable support with explicit argv and result handling.
- Caps Lock → F19 plus the system input-source shortcut is sufficient; the goal is improved responsiveness between the owner's two existing layouts.
- Kasa and general Shortcuts support are deferred.
- Follow requirements' explicit defaults unless actual testing or owner feedback warrants a recorded change.

## Verification of this checkpoint

- Reviewed both supplied screenshots; recorded essential launcher and settings layout details in REQUIREMENTS rather than relying on temporary image paths.
- Checked the empty working tree, system/toolchain, and relevant SDK definitions.
- Consulted primary Apple sources for event-tap/key-state APIs, key remapping, Process, and login items; links are in ARCHITECTURE.
- Documentation-only checkpoint: application build/tests are not applicable yet. All six Markdown files passed local-link and code-fence validation; `git diff --cached --check` passed with no whitespace errors.

## Next concrete action

When implementation is requested, begin **Stage 1**:

1. Read AGENTS, REQUIREMENTS, ARCHITECTURE, and the Stage 1 acceptance gate.
2. Inspect `git status` and toolchain again; add SwiftPM scaffolding, a minimal AppKit menu bar app, and a reproducible `.app` bundle script.
3. Prove the Right Command + Space chord with a minimal input-capable NSPanel before investing in full search/settings.
4. Record the actual grant requirements, shortcut coexistence, and signing behavior. Manual validation may require the owner to grant macOS permissions and temporarily release Raycast's conflicting chord.

## Open evidence gaps

These are implementation/test tasks, not unanswered planning questions that block scaffolding:

- Exact event-tap interception/coexistence and permissions on this macOS build.
- Local build identity stability for TCC, Automation, and start-at-login.
- Availability of a second monitor/external keyboard and an appropriate manual test opportunity.
- Owner's real Kibana script and its environment requirements. Use generic examples until provided.
- Whether F19-based system switching resolves the owner's perceived delay; requires hands-on verification.

## How to update this file

At the next session boundary replace the next-action section with the actual next step, update stage states, list changed code paths and checks with results, and record pending manual tests accurately. Keep this file concise enough to read at the start of every session. Use Git history for commit identifiers rather than inserting a self-referential hash into this checkpoint.
