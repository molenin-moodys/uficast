# Uficast

A personal, native macOS launcher for applications and local scripts, inspired by the small subset of Raycast its owner uses.

**Status:** planning complete; application implementation has not started.

## Agreed scope

- Swift + AppKit; English interface and project documentation.
- Open with **Right Command + Space**, keeping Left Command distinct.
- Find and launch applications, with exact aliases ahead of fuzzy name matches.
- Run local shell scripts, AppleScript, and other explicitly configured executables.
- Select a command with `k` → `Tab`, paste one text argument with `Cmd+V`, and press `Enter` to run it; support opening a generated URL.
- Raycast-inspired launcher and settings UI.
- Optional Caps Lock → F19 remapping; use macOS's input-source shortcut to switch between the two existing layouts.
- Build from source on each personal Mac. No App Store release or cloud service is planned.

## Planning documents

1. [Requirements and interaction details](docs/plan/REQUIREMENTS.md)
2. [Architecture and technical decisions](docs/plan/ARCHITECTURE.md)
3. [Implementation stages and acceptance criteria](docs/plan/IMPLEMENTATION_PLAN.md)
4. [Progress and next-session handoff](docs/plan/PROGRESS.md)

Start each implementation session with `PROGRESS.md`. Build instructions will be added when Stage 1 creates the application bundle.
