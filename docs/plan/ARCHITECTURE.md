# Architecture and decisions

Status: requested feature paths are implemented. See PROGRESS for actual tests, desktop observations and remaining acceptance checks.

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
Sources/UficastProcess/    Small C posix_spawn/poll process-group worker
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
| HotkeyService | Carbon launcher/app registration, per-binding conflict status, repeat debouncing and recovery. |
| InstanceCoordinator / InstanceLock | Process-held lock and local distributed notification to reveal the primary instance. |
| IconStore | Serial background 64-pixel PNG loading, cache, and targeted completion updates. |
| KeepAwakeService | Native owned power assertion, session expiry, and status notifications. |
| ApplicationCatalog | Discover app bundles, stable identity, refresh, metadata/icon loading. |
| KeyboardLayoutSearch | Query-only U.S./Russian physical-key alternatives; mapping precedes diacritic folding. |
| SearchIndex | Deterministic ranking across apps and scripts, alias precedence. |
| ConfigStore | Versioned JSON, validation, atomic writes, backups, migration. |
| ScriptRunner | Exact argv, interpreter, environment, async output, timeout and cancellation. |
| KeyboardRemapService | Read/merge/write Caps Lock mapping, ownership/conflict tracking and recovery. |
| LoginItemService | Optional start-at-login via SMAppService, current authorization/status. |

UI work stays on the main actor. Catalog work, process I/O, persistence, and remapping subprocesses must not block typing or hotkey callbacks. Avoid synchronous cross-actor waits in callbacks.

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
- Expand only search queries into deduplicated literal, Russian→U.S., and U.S.→Russian variants. Map before normalization so ё/й keep their physical-key identity. Rank by match tier, then literal/converted variant, then score/history. Apply to launcher and Settings search; never rewrite visible input, aliases, system layout, or script arguments.
- Use normalized case-insensitive comparison, stable rank tiers, and fuzzy subsequence scoring. History breaks ties within a tier; it must never outrank an exact alias. Do not store argument text in usage history.

## Persistence

Store private state under `~/Library/Application Support/Uficast/` with a versioned `config.json` and a last-known-good backup. Write through a temporary file and atomic replacement. Validate before changing live state; never overwrite unreadable or newer-schema data with defaults.

Conceptual configuration fields:

```text
schemaVersion
applicationRoots
applications: stableID -> alias?, isEnabled, lastKnownName?, fallbackPath?, hotkey?
scriptDirectories: local folder paths
scripts: id, name, alias?, enabled, fileURL, interpreter?, sourceDirectory?,
         requiresArgument, argumentPlaceholder, resultMode,
         workingDirectory?, environmentOverrides, timeoutSeconds
capsLockToF19Enabled
keyboard-recovery.json: separate local versioned ownership state
```

Schema version 1 contains applicationRoots, applications (including optional hotkey), scripts and capsLockToF19Enabled. The latter defaults off when decoding older schema-1 files; app hotkeys are optional. Launcher Cmd+Space is fixed. Persist only preferences; query actual login-item/permission/remap status from macOS. Back up/export configuration without treating it as executable shell source. Logs and local state are gitignored.

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

## Single instance and reopening

InstanceLock owns an open O_CLOEXEC file descriptor under Application Support/Uficast/instance.lock and uses nonblocking flock. Leave the inode in place; close releases ownership and the kernel also releases it on process exit. A second normal launch sends a user-scoped distributed notification and exits. The primary opens its existing launcher. Development-only diagnostics/previews bypass the application lock but never instantiate AppController or register shortcuts. Normal first launch shows the launcher immediately; the footer gear and Cmd+, open Settings.

## App-specific global shortcuts

Application overrides persist keyCode, Carbon modifier bits and a display label. Validation compares physical combinations, reserves Cmd+Space and rejects duplicate enabled app bindings. Carbon uses a per-binding pressed/released state. A launcher conflict does not prevent independent app shortcuts from registering; errors appear against the affected item. The Hotkey table column embeds the same native recorder as the inspector, with double-click activation and a border only while recording. Single clicks retain table selection. Escape cancels without invoking the save callback; only a valid chord commits, and explicit Delete or the adjacent × button clears. Focus loss, window deactivation/close and cell removal end recording and restore registrations. The local NSButton recorder uses ordinary responder events, temporarily suspending Uficast's registrations while focused. It does not observe global keys. App show/hide uses NSRunningApplication hide/unhide/activate and NSWorkspace launch, requiring no Accessibility.

## Icon loading and regression

IconStore renders each app icon into a 64×64 PNG on a serial background queue, transferring Data to the main actor and caching decoded immutable images in a strong, bounded 256-entry cache. Large multi-representation TIFFs are not retained. SwiftUI Settings observes completion. In the AppKit launcher, each requesting EntryRow receives its own weak completion callback, guarded by its represented URL; reloading the whole table per icon caused placeholder retention/jitter. The development-only --verify-native-icons check verifies the loaded bitmaps in 50 constructed cells, unchanged row geometry and unchanged scroll origin offscreen. AppKit may virtualize offscreen views; the check does not assert table cache identity.

## Keyboard profiles and multiple devices

The global hidutil table and macOS Modifier Keys are separate layers. The current keyboard had Caps Lock → Right Option in its current-host modifier profile; the HID table already contained Caps Lock → F19. Correcting only that system modifier source to Caps Lock resolved physical switching, as confirmed by the owner. Application diagnostics read only modifier-mapping preference keys and warn about conflicting profiles (including potentially disconnected keyboards); they do not rewrite those profiles automatically.

Wake and registry notifications for IOHIDDevice/IOHIDEventService trigger debounced re-publication of a still-owned global table for newly ready services, even if the global getter already reports F19. Existing externally owned identical mappings are not rewritten. The read/modify/write API is not atomic against independent external remappers; simultaneous physical-device testing remains pending. Normal Quit restores an owned mapping, while the saved enabled preference is reapplied on next launch.

## Keep Awake

KeepAwakeService owns at most one IOPM assertion. The native backend uses IOPMAssertionCreateWithName with kIOPMAssertPreventUserIdleSystemSleep; fixture tests inject a backend and never change power state. Renewals reuse the assertion, cancel the prior timer and increment a generation to reject stale expirations. State revisions prevent stale UI callbacks. Release failure retains ownership and publishes the error; normal quit waits for operations before releasing. The status icon is a cup while active and zzz while inactive, including initial startup. The decaffeine launcher entry also uses zzz. SavedKeepAwakeSession persists active/off mode and optional deadline in local UserDefaults (keepAwakeSession.v1), outside portable configuration. Startup restores indefinite or remaining timed sessions; expired/off sessions stay off. Startup observer snapshots cannot erase the remembered mode before restoration, and quit snapshots before releasing its assertion while suppressing cleanup updates. The kernel releases a process-owned assertion when its process exits. See Apple's [assertion contract](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep) for display/lid/explicit sleep behavior.

## Built-in launcher commands

BuiltInCommand defines stable builtin:caffeine / builtin:decaffeine identities, cafe / decafe abbreviations and cup / zzz symbols. AppController appends them to the launcher catalog without storing them as scripts or app overrides. They route directly to the shared KeepAwakeService enable/disable path; caffeine renews indefinite mode and decaffeine releases the app-owned assertion. There is no shell process or external app URL open. A busy operation is reported in the launcher. Fuzzy/layout search remains shared; an explicit user alias outranks a conflicting built-in abbreviation without invalidating existing configuration. Built-ins are currently launcher entries, not editable Commands records.

## Script folders

Configuration schema 1 adds default-empty scriptDirectories and optional ScriptCommand.sourceDirectory, preserving legacy decoding. ScriptFolderCatalog runs off the UI actor, enumerates direct non-hidden regular files, resolves symlinks, deduplicates canonical paths and reads at most 32 KiB of each candidate's header. Supported suffixes are sh/bash/zsh/py/applescript/scpt plus extensionless shebang files. Only initial comment-header Raycast title/argument1 data is parsed. One required text argument is supported; malformed or unsupported declarations produce notices. No discovery path executes scripts or copies their contents into the repository/configuration.

New commands receive path-derived IDs and inferred interpreters; existing commands keep all edited options and IDs. Manual entries win duplicate-file matches. Refresh prunes removed files only for successfully enumerated roots, retains commands from unavailable roots, and disconnect removes only managed records. Files are never deleted. Editing a managed path detaches it with a new identity so reindexing the original file cannot collide. Settings exposes folder add/refresh/disconnect; refresh occurs after connecting/importing directories, on successful configuration recovery and at startup. There is no recursive traversal or live folder watcher in this increment; script contents are always read from the original path at execution.

## Transactional alias cells

AliasEditor embeds a native label, NSTextField and removal button in both the Alias column and inspector. Double-click activates a local draft; Enter submits through SettingsModel.saveAlias and existing configuration validation. Duplicate/invalid input keeps editing open; Escape, focus/window loss, removal/reuse or disabling discards the draft without a save callback. The cross explicitly commits nil. Neither alias editing nor cancellation changes hotkey registration. Public preview fixture application IDs now use the valid app: namespace so native editing checks exercise real validation.

## Script failure presentation and argument styling

The native text-view argument surface uses a subtle appearance-dependent fill with transparent scroll/clip backgrounds. Text and placeholder share the leading inset and no additional text-container padding; both empty/filled light/dark previews are checked.

Owner steering supersedes closing the launcher on accepted execution: scripts keep their current view while running, then close on success or show a bounded lower error section on failure. ScriptResult.failureDescription includes termination/exit and stderr, with stdout fallback for scripts that print validation failures there. The exact submitted argument and last failure live only in memory. Edit Input restores/selects it; it never executes. A presentation UUID guards current UI updates; user navigation/dismissal invalidates it and stale runs cannot overwrite newer input or reopen the panel. Dismissal, including application hide, clears failure/input and invalidates both run IDs before checking visibility. Late completions are ignored before storing any failure. The next deliberate open is clean. Existing cancellation/recent-run and URL-success-only rules remain in place.

## Local keyboard commands

AppMenu builds standard application/File/Edit/Window menus and a hidden-but-active Cmd+P Settings alias while preserving visible Cmd+,. Cmd+F focuses launcher search or requests Commands search focus through SwiftUI FocusState. Cmd+W uses native performClose; the launcher routes it through dismiss for cleanup. SettingsWindow handles only window-local Esc events: attached sheets keep native dispatch, active inline edits cancel first, otherwise Settings closes. Native view key equivalents continue to handle recorded chords before menus. Menu actions do not register more global shortcuts. References: [Apple shortcuts](https://support.apple.com/en-us/102650), [Cocoa key-equivalent routing](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingKeyEvents/HandlingKeyEvents.html).

## Experimental menu-bar calendar

MenuBarClockController updates the existing NSStatusItem, never creating a second permanent button. Clock enabled/Show Icon/format live in schema-1 menuBarClock with default decoding for older files. Turning off the clock restores the existing cup/zzz state. The clock's tooltip and menu still expose Keep Awake; power behavior does not change.

Read-only inspection of installed Day-O 3.0.1 revealed SIDatePicker inheriting NSDatePicker and using setDatePickerStyle. MenuBarCalendarView embeds the same public AppKit clockAndCalendar control, unbordered with transparent background and vibrancy. sizeToFit produces a 139×148-point picker; padding makes the custom menu view approximately 163×164 points. Flexible left/right margins keep the picker centered if NSMenu widens the wrapper to fit command rows. No manual grid, date arithmetic, copied resources, calendar-account permission or Day-O runtime dependency. NSMenu owns tracking/outside-click/Esc; NSDatePicker owns month navigation and Today. The menu delegate resets dateValue on open.

The root menu contains the calendar, Open Launcher, Settings, Date & Time, a Keep Awake submenu and Quit. Long status rows no longer dictate its width. General retains shortcut diagnostics/retry and application refresh; latest action status moves to General / Recent Runs.

The clock uses one-shot Timer deadlines on the next integral Unix second, registered for common and event-tracking run-loop modes, with zero tolerance. Every tick redraws from current Date and computes a fresh boundary. System-clock/locale/time-zone notifications and AppController's existing wake handler resynchronize it. Stop invalidates the timer and unregisters observers. This avoids launch-phase drift and missed updates during menu tracking; it is not a real-time rendering guarantee if the main thread is blocked.

Development-only --preview-calendar renders a deterministic July 2027 NSDatePicker in either appearance without AppController/configuration/services. --verify-menu-clock temporarily creates and removes a status item, checks native sizing, reopening reset, icon/fallback settings, three actual tick phases in menu-tracking mode and a synthetic clock-change notification; it does not alter the machine's date, hotkeys, mappings, login items or power state.

Calendar menu polish: status-menu Settings/Quit items have no key equivalents, avoiding a trailing shortcut column; AppMenu still supplies Cmd+, / Cmd+P and Cmd+Q. The status icon now matches the owner-authorized Day-O reference: 22×18-point calendar geometry, three rounded top bindings, no header rule, 2-point horizontal image padding and a centered 9-point bold system date at y=3. Resolution-independent NSImage drawing replaces lockFocus. Geometry and drawing constants were inspected read-only; no Day-O PDF/binary is bundled or required at runtime.
