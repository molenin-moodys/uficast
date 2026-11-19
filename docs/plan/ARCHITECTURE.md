# Architecture and decisions

Status: native scaffold implemented; real desktop delivery remains pending manual verification. Later sections describe remaining implementation.

## Build and runtime

- Use Swift 6.2 and Swift Package Manager, with no initial third-party dependencies. Keep platform-independent models/search in a library target and the AppKit executable in another target.
- Package the executable and resources into `Uficast.app` using a repository build script and an explicit `Info.plist`. Support release builds from Command Line Tools; an Xcode project must not be mandatory.
- AppKit owns app lifecycle, `NSStatusItem`, `NSPanel`, focus, text input, menus, and keyboard handling. SwiftUI hosted inside AppKit may implement Settings if it reproduces the required table and editing behavior well. Prefer native AppKit controls where SwiftUI focus/key handling becomes unreliable.
- Use an accessory app activation policy / agent app bundle. Supply standard Edit menu actions so Cmd+V and related shortcuts work without manual pasteboard interception.
- Keep a stable bundle identifier and documented install location. Begin with local ad-hoc signing; record whether rebuilding causes Automation grants to need renewal. If a local signing identity is needed for stable Automation consent behavior, document that result rather than promising ad-hoc identity stability.
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

Stage 1 created the package, core/app/test targets, resources, and build/test scripts. Introduce further subdivisions only as code warrants them. The Command Line Tools installation includes Testing.framework but SwiftPM did not discover it; test.sh supplies its framework path/rpath when present and disables unavailable XCTest.

## Service boundaries

| Component | Responsibility |
| --- | --- |
| AppController | Lifecycle, menu bar, wiring services, current launch/run status. |
| LauncherPanelController | Presentation, screen/Space placement, search vs argument mode, focus restoration. |
| HotkeyService | Carbon Cmd+Space registration, conflict status, repeat debouncing and recovery. |
| ApplicationCatalog | Discover app bundles, stable identity, refresh, metadata/icon loading. |
| SearchEngine | Deterministic ranking across apps and scripts, alias precedence. |
| ConfigStore | Versioned JSON, validation, atomic writes, backups, migration. |
| ScriptRunner | Exact argv, interpreter, environment, async output, timeout and cancellation. |
| KeyboardRemapService | Read/merge/write Caps Lock mapping, ownership/conflict tracking and recovery. |
| LoginItemService | Optional start-at-login via SMAppService, current authorization/status. |

UI work stays on the main actor. Catalog work, process I/O, persistence, and remapping subprocesses must not block typing or the event-tap callback. Avoid synchronous cross-actor waits in callbacks.

## Command + Space without Accessibility

The owner changed the original right-only requirement to ordinary Cmd+Space and explicitly ruled out Accessibility. This supersedes the earlier event-tap design.

- Register Cmd+Space using Carbon `RegisterEventHotKey` with `cmdKey` and `kEventHotKeyExclusive`. Either Command key works. Install pressed/released handlers and debounce repeats until release.
- Do not install keyboard event taps, global keyboard monitors, or call Accessibility/Input Monitoring preflight/request APIs. Normal text-field accessibility labels do not require a privacy grant.
- Report registration errors, including another app's exclusive registration. A successful registration alone does not establish that Spotlight or another system shortcut will yield the chord; show static setup guidance and verify delivery manually.
- Never change Spotlight/Raycast shortcut assignments automatically. The owner releases conflicting chords in their settings. Open Launcher from the menu always remains available.
- Unregister on quit/retry; retry after wake. Carbon registration is main-thread-only. Secure Input/fullscreen behavior and delivery still require actual desktop evidence.
- The packaged `--diagnostics` mode reports bundle identity and the no-Accessibility design without registering a hotkey or asking for permissions.

The authoritative installed SDK `CarbonEvents.h` documents RegisterEventHotKey and exclusive conflicts. Apple's [developer forum explanation](https://developer.apple.com/forums/thread/763878) confirms current modifier restrictions; Cmd is an accepted modifier. Do not infer runtime delivery from registration success.

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
applicationRoots
applications: stableID -> alias?, enabled, fallbackURL?
scripts: id, name, alias?, enabled, fileURL, interpreter?,
         requiresArgument, argumentPlaceholder, resultMode,
         workingDirectory?, environmentOverrides, timeoutSeconds
keyboard: capsLockToF19Enabled, mappingOwnership/recoveryState
```

The implemented schemaVersion 1 currently contains applicationRoots, applications (including lastKnownName/fallbackPath), and scripts; launcher Cmd+Space is fixed. Keyboard preferences will be added with compatible decoding when implemented. The sketch above records future fields too. Persist only preferences; query actual login-item/permission/remap status from macOS. Back up/export configuration without treating it as executable shell source. Logs and local state are gitignored.

## Script execution

- Implemented deviation: use a small C `posix_spawn` worker wrapped by the Swift ScriptRunner actor so process groups and descendant cleanup are explicit. All execution still uses an executable and an argument array; no shell interpolation. Shell: interpreter, script path, then optional argument. AppleScript: `/usr/bin/osascript`, script path, then optional argument, consumed by `on run argv`. Executable/shebang scripts: file URL and optional argument.
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

- The UI toggle explicitly applies the mapping. Read the full existing mapping, preserve unrelated entries, and record ownership before changing Caps Lock. The implemented v1 refuses to replace a competing Caps Lock mapping; explain the conflict and let its original tool remove it first.
- Treat existing identical Caps Lock → F19 mappings as externally managed unless ownership is known; do not remove them on disable. Persist sufficient recovery state before the first mutation.
- Disable removes/restores only this app's still-owned entry; retain other mappings and do not overwrite an entry changed by another tool. Document the remaining race limitations of hidutil's read/modify/write API.
- Reconcile on app startup and relevant wake/device reconnect events when enabled. Avoid a polling loop or repeatedly fighting another remapper. Show status when user intervention is needed.
- Scope v1 to the app's lifetime plus explicitly enabled start-at-login. On normal quit restore owned mappings, retaining the preference for next launch. A crash may leave a mapping until recovery/restart; detect and recover on the next start. Verify actual behavior on macOS 26 and document it.
- Guide the owner to Keyboard → Keyboard Shortcuts → Input Sources to assign F19 to the appropriate system switching action. Provide a link to the relevant settings pane when possible; do not rewrite undocumented shortcut preferences.
- The app does not implement input-source switching itself. Test perceived responsiveness with the owner's two layouts; no zero-delay guarantee follows from changing the key code.

TN2450 is archival documentation. Its reboot/device-service lifetime and privileges statements are design inputs to verify on this system, not evidence that a runtime test has passed.

## Primary references

- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel) and [nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel): panel behavior.
- Historical, superseded API reference: [CGEventFlags.maskCommand](https://developer.apple.com/documentation/coregraphics/cgeventflags/maskcommand): aggregate Command state.
- Historical, superseded API references: [CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) and [CGEventSource.keyState](https://developer.apple.com/documentation/coregraphics/cgeventsource/keystate(_:key:)): event interception and key-state APIs.
- Installed macOS SDK: `Carbon.framework/Frameworks/HIToolbox.framework/Headers/Events.h` defines `kVK_RightCommand = 0x36`, `kVK_Command = 0x37`, `kVK_Space = 0x31`; `IOKit.framework/Headers/hidsystem/IOLLEvent.h` defines separate left/right Command masks. Recheck SDK locations in implementation rather than hard-coding this machine's paths.
- [TN2450: Remapping Keys](https://developer.apple.com/library/archive/technotes/tn2450/) and [Apple IOHID usage tables](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDUsageTables.h): remapping mechanism/usages.
- [Foundation Process](https://developer.apple.com/documentation/foundation/process): executable and argv execution.
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice): login-item integration.
- [macOS input-source settings](https://support.apple.com/en-sa/guide/mac-help/-mchl84525d76/mac): built-in switching options.

Stage 3 uses an actor ConfigStore plus a main-actor ObservableObject for a SwiftUI-hosted Settings window. Store tests inject a temporary directory and never write personal configuration. The optional Testing/Foundation cross-import module is absent from this CLT installation; test.sh disables cross-import overlays only in that incomplete setup.

The native worker polls both output streams, checks cancellation/deadlines between bounded reads, and leaves the leader waitable (waitid with WNOWAIT) until group cleanup finishes. This prevents signaling a reused PID. A final managed-group cleanup also handles children that close their streams and outlive a successful shell. Scripts intentionally starting detached daemons must manage that lifecycle themselves. Crash/force-quit cleanup is not guaranteed; normal app quit waits for runner cancellation. Development-only --preview-launcher/--preview-settings render deterministic views offscreen without constructing AppController, registering shortcuts or modifying personal configuration.

Stage 6 recovery is stored separately in keyboard-recovery.json with its own version. Default-off launch does not invoke hidutil unless a prior ownership record needs recovery. Registry-only IOKit service notifications observe device lifecycle without opening HID devices. SMAppService registration changes occur only through the explicit startup control; status is queried from macOS. Keep Awake is a new owner-requested addition using process-owned IOPM idle-sleep assertions; no persisted active state or subprocess is planned.
