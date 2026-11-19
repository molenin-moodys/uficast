# Uficast

A personal, native macOS launcher for applications and local scripts, inspired by the small subset of Raycast its owner uses.

**Status:** native app catalog and fuzzy search implemented; settings/aliases and scripts are next. Global shortcut delivery and desktop UI acceptance remain pending manual verification.

## Agreed scope

- Swift + AppKit; English interface and project documentation.
- Open with **Command + Space**, using either Command key; no Accessibility or Input Monitoring requirement.
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

Start each implementation session with `PROGRESS.md`.

## Build and test

Requires macOS 26, Swift 6.2 and Command Line Tools. No external packages.

```sh
scripts/test.sh
scripts/build.sh
open dist/Uficast.app
```

Use the menu bar's **Open Launcher**, **Settings…**, **Retry Shortcut** and **Quit**. The global shortcut uses Carbon registration and never requests Accessibility or Input Monitoring. Release conflicting Cmd+Space shortcuts in Spotlight/Raycast yourself; Uficast does not change their settings. A successful registration does not prove a system shortcut yields the chord.

Build output is `dist/Uficast.app`, locally ad-hoc signed. `scripts/build.sh debug` builds a debug bundle. Optionally set `UFICAST_SIGN_IDENTITY` to an existing signing identity. Avoid replacing the bundle while it is running. Script Automation consent may need renewal after ad-hoc rebuilds; a stable installation path is recommended.

Read-only diagnostics (no registration or permission prompts):

```sh
dist/Uficast.app/Contents/MacOS/Uficast --diagnostics
```

See [manual verification](docs/MANUAL_TESTS.md). Pure tests and signing checks do not prove real desktop shortcut delivery.

Application discovery uses `/Applications`, `/System/Applications` and `~/Applications`. Use **Refresh Applications** after installing an app; default root changes are also observed. Search supports fuzzy abbreviations, Up/Down selection and Enter to launch/activate. Usage ordering is currently in memory. `--catalog-summary` prints a read-only discovery count/timing without launching apps.
