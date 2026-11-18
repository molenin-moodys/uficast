# Architecture and decisions

Status: implementation design, with explicit spikes where real macOS behavior must be established. No application code exists yet.

## Build and runtime

- Use Swift 6.2 and Swift Package Manager, with no initial third-party dependencies. Keep platform-independent models/search in a library target and the AppKit executable in another target.
- Package the executable and resources into `Uficast.app` using a repository build script and an explicit `Info.plist`. Support release builds from Command Line Tools; an Xcode project must not be mandatory.
- AppKit owns app lifecycle, `NSStatusItem`, `NSPanel`, focus, text input, menus, and keyboard handling. SwiftUI hosted inside AppKit may implement Settings if it reproduces the required table and editing behavior well. Prefer native AppKit controls where SwiftUI focus/key handling becomes unreliable.
- Use an accessory app activation policy / agent app bundle. Supply standard Edit menu actions so Cmd+V and related shortcuts work without manual pasteboard interception.
- Keep a stable bundle identifier and documented install location. Begin with local ad-hoc signing; record whether rebuilding causes privacy grants to need renewal. If a local signing identity is needed for stable TCC behavior, document that result rather than promising ad-hoc identity stability.
- Local unsandboxed execution is appropriate for the personal app's configured scripts. No App Store provisioning, network backend, or telemetry.

## Proposed source layout

```text
Package.swift
Sources/UficastCore/       Models, ranking, config validation, execution contracts
Sources/Uficast/           AppKit lifecycle, panel, settings, platform services
Tests/UficastCoreTests/    Ranking, config, argument/result contracts
Tests/UficastTests/        Platform/service integration tests where practical
Resources/                Info.plist, application assets
scripts/                  Build/package and verification entry points
examples/                 Portable scripts using public/example URLs
docs/plan/                Requirements, architecture, stages, and progress
```

Paths are proposed, not claims about existing files. Introduce subdivisions only as code warrants them.

## Service boundaries

| Component | Responsibility |
| --- | --- |
| AppController | Lifecycle, menu bar, wiring services, current launch/run status. |
| LauncherPanelController | Presentation, screen/Space placement, search vs argument mode, focus restoration. |
| HotkeyService | Side-specific trigger, permissions, event consumption and recovery. |
| ApplicationCatalog | Discover app bundles, stable identity, refresh, metadata/icon loading. |
| SearchEngine | Deterministic ranking across apps and scripts, alias precedence. |
| ConfigStore | Versioned JSON, validation, atomic writes, backups, migration. |
| ScriptRunner | Exact argv, interpreter, environment, async output, timeout and cancellation. |
| KeyboardRemapService | Read/merge/write Caps Lock mapping, ownership/conflict tracking and recovery. |
| LoginItemService | Optional start-at-login via SMAppService, current authorization/status. |

UI work stays on the main actor. Catalog work, process I/O, persistence, and remapping subprocesses must not block typing or the event-tap callback. Avoid synchronous cross-actor waits in callbacks.

## Right Command + Space: resolve first

The aggregate Command flag does not distinguish left and right. A successful generic Cmd+Space implementation does not satisfy this requirement.

- Prototype an active session-level Core Graphics event tap. Use physical key codes (`kVK_RightCommand`, `kVK_Command`, `kVK_Space`) and public side-specific state/flags to identify Right Command. Seed/resynchronize modifier state so installation while a modifier is held, missed flags changes, and sleep/wake do not leave a stuck state.
- Default chord policy: Right Command down, Left Command up, and no extra Shift/Option/Control/Fn. Test both modifier press orders and both Command keys held. Document any intentional policy adjustment.
- Consume only the matched Space key-down, its repeats, and corresponding key-up. Pass unrelated events through. Track a consumed press independently of modifier release order, so key-up is handled correctly if Command is released first.
- Debounce repeats, recover a tap disabled by timeout/user input, and make permission denial/revocation visible. Keep a menu action available when the global trigger is unavailable.
- Check Accessibility / event-listening preflight and request APIs as applicable. Determine the minimum actual grants on macOS 26 during the spike; do not assume observing and suppressing events have identical requirements.
- Validate coexistence with Spotlight's generic Cmd+Space and Raycast. Do not silently change either app's shortcuts. If system interception defeats the proposed tap, resolve and record a supported alternative before building the rest of the UI.
- Secure Input and the login/lock screen may limit global event handling. Record actual behavior and recovery; do not build a driver to bypass it.

## Panel and focus

Use a borderless, floating `NSPanel` with `.nonactivatingPanel`, a key-capable subclass, and appropriate Space/full-screen collection behavior. The panel must accept keyboard input without unnecessarily activating the owning app. Treat focus behavior as something to test, not something implied by the style mask alone.

Keep explicit states: `hidden`, `search(query, selection)`, and `argument(commandID, value, previousQuery)`. Execution is a separate service state so hiding the panel does not terminate a run. On success, allow the launched destination to receive focus; on cancellation, restore the previously active app when still valid.

## Catalog and search

- Enumerate configured roots in the background, skip nested helper bundles by default, and cache metadata/icons separately from search keys.
- Use bundle identifier as an app's primary persisted identity, with an explicit fallback to canonical bundle URL. Resolve moves/duplicates deterministically and avoid merging unrelated apps just because names match.
- Refresh on startup, app install/remove/root changes where observable, and explicit Refresh. Keep previous results usable during refresh. No dependency on complete Spotlight indexing.
- Combine app records with script records and user overrides. Persist aliases/enabled status separately from the rebuildable discovery cache.
- Use normalized case-insensitive comparison, stable rank tiers, and fuzzy subsequence scoring. History breaks ties within a tier; it must never outrank an exact alias. Do not store argument text in usage history.

## Persistence

Store private state under `~/Library/Application Support/Uficast/` with a versioned `config.json` and a last-known-good backup. Write through a temporary file and atomic replacement. Validate before changing live state; never overwrite unreadable or newer-schema data with defaults.

Conceptual configuration fields:

```text
schemaVersion
general: launcherShortcut, applicationRoots
applications: stableID -> alias?, enabled, fallbackURL?
scripts: id, name, alias?, enabled, fileURL, interpreter?,
         requiresArgument, argumentPlaceholder, resultMode,
         workingDirectory?, environmentOverrides, timeoutSeconds
keyboard: capsLockToF19Enabled, mappingOwnership/recoveryState
```

This is a contract sketch, not a final serialized schema. Persist only preferences; query actual login-item/permission/remap status from macOS. Back up/export configuration without treating it as executable shell source. Logs and local state are gitignored.

## Script execution

- Use `Process` with an executable URL and an argument array. Shell: interpreter, script path, then optional argument. AppleScript: `/usr/bin/osascript`, script path, then optional argument, consumed by `on run argv`. Executable/shebang scripts: file URL and optional argument.
- Never interpolate the user's input into `sh -c`, `eval`, or AppleScript source. Empty optional/no-argument commands receive no extra argv element.
- Default working directory to the script's parent directory. Use an explicit, configurable PATH including `/opt/homebrew/bin`, `/usr/local/bin`, and standard system directories; don't silently source `.zshrc`. Allow per-command environment overrides without writing values into diagnostics.
- Drain stdout and stderr concurrently, even when output is discarded. Bound captured output (initial default: 1 MiB per stream) while continuing to drain or terminating with a clear reason; avoid pipe deadlock.
- Default timeout: 30 seconds, editable per command. Define cancellation and child-process cleanup during implementation; test a script spawning a child, not just a single sleep process. Do not promise to stop deliberately detached daemons.
- Prevent duplicate concurrent execution of the same command in v1. Keep other commands and the launcher usable during a run.
- Implement the explicit `discard` / `openURL` contracts from REQUIREMENTS. In URL mode, open once only after successful exit and validation.
- Store bounded recent-run metadata and failure text in memory initially. Do not persist arguments, full URLs, environment values, or arbitrary stdout by default.
- AppleScript controlling another app may trigger macOS Automation consent. Add the appropriate bundle usage description and verify real grant attribution when launched from the packaged app; don't assume Terminal's permissions apply.

## Caps Lock → F19

Use `/usr/bin/hidutil` via `Process` initially. Apple's TN2450 documents `UserKeyMapping`; the HID usage values are Caps Lock `0x700000039` and F19 `0x70000006E`. These are HID usages, not AppKit virtual key codes.

- The UI toggle explicitly applies the mapping. Read the full existing mapping, preserve unrelated entries, and remember the prior Caps Lock mapping. Detect a competing Caps Lock mapping before replacing it and explain the conflict in Settings.
- Treat existing identical Caps Lock → F19 mappings as externally managed unless ownership is known; do not remove them on disable. Persist sufficient recovery state before the first mutation.
- Disable removes/restores only this app's still-owned entry; retain other mappings and do not overwrite an entry changed by another tool. Document the remaining race limitations of hidutil's read/modify/write API.
- Reconcile on app startup and relevant wake/device reconnect events when enabled. Avoid a polling loop or repeatedly fighting another remapper. Show status when user intervention is needed.
- Scope v1 to the app's lifetime plus explicitly enabled start-at-login. On normal quit restore owned mappings, retaining the preference for next launch. A crash may leave a mapping until recovery/restart; detect and recover on the next start. Verify actual behavior on macOS 26 and document it.
- Guide the owner to Keyboard → Keyboard Shortcuts → Input Sources to assign F19 to the appropriate system switching action. Provide a link to the relevant settings pane when possible; do not rewrite undocumented shortcut preferences.
- The app does not implement input-source switching itself. Test perceived responsiveness with the owner's two layouts; no zero-delay guarantee follows from changing the key code.

TN2450 is archival documentation. Its reboot/device-service lifetime and privileges statements are design inputs to verify on this system, not evidence that a runtime test has passed.

## Primary references

- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel) and [nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel): panel behavior.
- [CGEventFlags.maskCommand](https://developer.apple.com/documentation/coregraphics/cgeventflags/maskcommand): aggregate Command state.
- [CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) and [CGEventSource.keyState](https://developer.apple.com/documentation/coregraphics/cgeventsource/keystate(_:key:)): event interception and key-state APIs.
- Installed macOS SDK: `Carbon.framework/Frameworks/HIToolbox.framework/Headers/Events.h` defines `kVK_RightCommand = 0x36`, `kVK_Command = 0x37`, `kVK_Space = 0x31`; `IOKit.framework/Headers/hidsystem/IOLLEvent.h` defines separate left/right Command masks. Recheck SDK locations in implementation rather than hard-coding this machine's paths.
- [TN2450: Remapping Keys](https://developer.apple.com/library/archive/technotes/tn2450/) and [Apple IOHID usage tables](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDUsageTables.h): remapping mechanism/usages.
- [Foundation Process](https://developer.apple.com/documentation/foundation/process): executable and argv execution.
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice): login-item integration.
- [macOS input-source settings](https://support.apple.com/en-sa/guide/mac-help/-mchl84525d76/mac): built-in switching options.
