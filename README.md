# Uficast

A personal, native macOS launcher for applications and local scripts, inspired by the small subset of Raycast its owner uses.

**Status:** native app catalog and fuzzy search implemented; persistent settings/aliases and argument scripts are implemented; Caps Lock/login lifecycle is next. Global shortcut delivery and desktop UI acceptance remain pending manual verification.

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

## Settings and aliases

Open **Settings… → Commands**, select an app, enter an alias and click **Apply**. Enabled controls visibility in launcher search. Exact aliases always outrank name/fuzzy matches; enabled commands cannot share an alias. General contains application roots, refresh, import/export and backup recovery.

Private JSON lives in `~/Library/Application Support/Uficast/config.json`, with `config.backup.json`. Saves are atomic. Corrupt/unsupported files are preserved and editing is disabled; explicit backup recovery preserves the replaced file as `config.recovered-<id>.json`. A future schema cannot be overwritten by this older app. Export/import preserves machine-specific paths; locate missing scripts/apps on the new Mac.

## Script commands

In Commands, use **+ → Add Script…**. Choose a local script, set its interpreter (for example `/bin/zsh`, `/bin/bash`, `/usr/bin/osascript`, or `/usr/bin/python3`) and an alias. An empty interpreter runs an executable file using its shebang. Selection offers **Edit…** and **Delete**; deleting a command leaves its source file intact.

For the `k` workflow, configure [browser-search.py](examples/browser-search.py), interpreter `/usr/bin/python3`, alias `k`, one required argument, placeholder `log_stream`, and **Open stdout URL in browser**. In the launcher: `k` → Tab → Cmd+V → Enter. This example generates an encoded example.com URL; it does not contain a real Kibana endpoint. [Shell](examples/echo-argument.sh) and [AppleScript](examples/echo-argument.applescript) examples are also included.

Default result handling runs for side effects and ignores stdout (the script can call `/usr/bin/open` itself). URL mode opens exactly one valid HTTP(S) URL only after exit code zero. Arguments are passed as one argv value; `.zshrc` is not sourced. PATH includes Homebrew and standard system directories; per-command environment overrides are supported. The default working directory is the script folder and the default timeout is 30 seconds.

General → Recent Runs shows active commands, Cancel controls and the ten most recent outcomes in memory. Each command can run once concurrently; different commands can overlap. Output capture is bounded to 1 MiB per stream while both pipes continue draining. Normal quit cancels managed process groups; deliberately detached daemons and force-quit/crash cleanup are outside that guarantee. AppleScript controlling other applications may need **Automation** consent; scripts depending on Accessibility are unsupported under the no-Accessibility requirement.

## Development previews

After a build, these commands render fixture views offscreen without registering shortcuts or modifying user configuration:

```sh
mkdir -p .build/previews
dist/Uficast.app/Contents/MacOS/Uficast --preview-launcher .build/previews/launcher.png
dist/Uficast.app/Contents/MacOS/Uficast --preview-launcher .build/previews/argument.png --argument
dist/Uficast.app/Contents/MacOS/Uficast --preview-settings .build/previews/settings.png
```

Previews verify layout; desktop keyboard delivery, focus, paste and browser behavior require the manual checklist.
