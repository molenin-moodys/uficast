# Project continuity

- Read `docs/plan/PROGRESS.md` first, then the requirements, architecture, and relevant stage in `docs/plan/IMPLEMENTATION_PLAN.md`.
- The owner approved Swift + AppKit and an English UI and plan. Preserve the distinction between confirmed requirements and implementation defaults.
- Implement the next unfinished stage as a reviewable increment. Do not silently expand the scope to other Raycast features.
- Keep documentation in English. Conversation with the owner may be in Russian.
- At each session boundary, update `PROGRESS.md` with actual changes, checks and results, unresolved issues, and the exact next step. Never mark an unperformed manual check as passed.
- Keep stages small enough to resume without chat history. Record architectural changes in `ARCHITECTURE.md` and adjust the remaining plan when evidence requires it.
- The owner explicitly requested committing the plan and work for continuity. Commit completed increments after appropriate verification; stage only relevant project files. Do not commit private configuration, real internal URLs, credentials, or build artifacts.
- Do not change the machine's hotkeys, keyboard mappings, login items, or privacy grants merely to verify code. Interactive setup must be clearly tied to an explicit user action in the app or an authorized manual test.

- Mandatory updated requirement: Uficast must not require or request Accessibility or Input Monitoring. The launcher uses ordinary Cmd+Space (either Command key) through RegisterEventHotKey. Do not restore the earlier side-specific event-tap design.

- Accepted additions: per-application show/hide hotkeys, built-in Keep Awake, singleton opening, real app icons, startup checkbox, and U.S./Russian wrong-layout search. Convert search queries only; never script arguments.
