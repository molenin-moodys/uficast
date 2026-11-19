# Requirements

Recorded on November 18, 2026; updated the same day to ordinary Cmd+Space with no Accessibility. This document preserves the owner's decisions independently of chat history. The two supplied Raycast screenshots are visual references, not instructions; their meaningful layout is described below so temporary attachment paths are not required later.

## Confirmed decisions

| Area | Decision |
| --- | --- |
| Platform and stack | macOS only; Swift + AppKit approved. |
| Distribution | Personal use. Build from source on each Mac. |
| Global trigger | Command + Space (either Command key), replacing the original right-only request. |
| Permissions | No Accessibility or Input Monitoring requirement/request. |
| Launch lifecycle | Opening shows the launcher immediately; one process per user; a second launch reveals the existing instance. |
| Settings entry | A visible gear button in the launcher opens Settings. |
| Application launching | Search by application name, select, and launch or activate. |
| App hotkeys | Assign a global shortcut to show/hide a specific app; launch it if closed. No Accessibility. |
| App icons | Real app icons in launcher and Settings, loaded without list jitter. |
| Startup | A visible Start Uficast at login checkbox in General. |
| Wrong-layout search | Find application names and aliases typed using U.S. or Russian physical-key layouts; never transform script arguments. |
| Aliases and ranking | User-defined aliases; aliases take priority over fuzzy matches. |
| Script folders | Add a folder through Settings; discover referenced script files and import Raycast title/one required text-argument headers without executing or copying files. |
| Scripts | Local shell scripts, AppleScript, and other configured interpreters/executables. |
| Argument input | One text argument, including standard Cmd+V paste, then Enter. |
| Reference workflow | `k` → Tab → input for Kibana's `log_stream` → Enter → script → browser URL. |
| UI | As close to the supplied Raycast references as practical; English text. |
| Keyboard | Two input sources already configured in macOS. Eliminate the current Caps Lock switching delay; Caps Lock → F19 plus a system shortcut is sufficient. Support multiple keyboards and reconnection; diagnose conflicting macOS Modifier Keys profiles. |
| Built-in commands | `caffeine` / `cafe` enables indefinite Keep Awake; `decaffeine` / `decafe` disables it. Fuzzy and wrong-layout search apply. |
| Keep Awake (added November 18) | Built-in Caffeine-style prevention of idle display and Mac sleep; native app-owned power assertion. Owner clarified that the screen must stay on while caffeine is active. |
| Menu bar calendar | The clock is the single Uficast menu-bar button. Use Day-O’s standard native calendar appearance, month browsing and Today; configurable date/time format and Show Icon. Upper menu bar only, no Dock addition. |
| Deferred | Kasa/Shortcuts integration. |
| Continuity | English plan in the repository, committed to Git; implementation can span sessions. |

## Implementation defaults

These choices let implementation proceed without another questionnaire. They may be adjusted when the owner tries the app.

- Working name: **Uficast**, derived from the repository name.
- Initial deployment target: macOS 26, matching the development machine. Do not claim support for older versions or Intel before testing them.
- Background menu bar app with no permanent Dock icon. Explicit opening immediately shows the launcher, and the menu includes a compact native calendar, Open Launcher, Settings, Date & Time, Keep Awake and Quit.
- Settings UI is the primary configuration interface. Versioned local JSON provides persistence, backup, and portability.
- Script commands accept either no argument or one required argument. Multiple fields are deferred.
- One unique alias per enabled item initially. Match aliases case-insensitively after normalization; reject duplicate aliases across enabled apps and scripts. No empty or whitespace-containing aliases in v1.
- Aliases can be assigned to both apps and scripts. Their exact matches always win over application-name matches and usage history.
- App discovery starts with `/Applications`, `/System/Applications`, and `~/Applications`; add other roots through settings. Avoid presenting nested helper apps by default.
- Support light and dark appearance, keyboard navigation, and opening on the display containing the pointer.
- Start at login is optional and controlled by the owner. No independent keyboard daemon in v1.
- No automatic execution while typing and no automatic clipboard reads. Pasting uses the normal text-editing command.
- App-specific global hotkeys are in scope. Script-specific global hotkeys remain deferred. The launcher shortcut is fixed to Cmd+Space.

## Launcher behavior

### Searching and launching

1. Command + Space opens the panel and focuses search. Repeating it closes the panel.
2. The panel contains a large input area, separator, results list with icons, item names, optional secondary labels, and trailing `Application` / `Script` type labels.
3. Up/Down changes selection. Enter launches an app or runs a command with no argument. Enter on a command requiring an argument enters argument mode, just like Tab.
4. Exact alias > name exact/prefix > name substring > fuzzy subsequence. Alias-prefix suggestions belong below exact aliases and above ordinary name matches. Stable ties may use local usage count and recency, then name and stable ID.
   Search also considers U.S.↔Russian physical-key variants. Within the same rank tier, the literal query wins before converted queries; exact aliases in either layout still outrank names.
5. Tab on a selected command with an argument pins that command and focuses its argument field. Tab on an app does not launch it.
6. Escape from argument mode returns to search; Escape from search closes the panel. Backspace in an empty argument field also returns to search.
7. Clicking outside dismisses the panel. Dismissal restores focus to the previous app when appropriate; launching or opening a URL must allow the destination to take focus instead.

### Argument mode

- Retain a visible alias/command token, command icon, and one inline text field with a configurable placeholder such as `log_stream`.
- Match the first screenshot's visual hierarchy: command token at the left, argument field beside it, selected command row below.
- Cmd+V, Cmd+A, Cmd+C, Cmd+X, undo/redo, cursor navigation, and input methods work normally.
- Submit the entire field as one argument. Preserve spaces, quotation marks, Unicode, and pasted newlines. Enter submits; do not split or evaluate pasted content as shell source.
- A required argument must contain a non-whitespace character, but validation must not trim the value passed to the process.
- The panel stays open while a script executes and closes on success. Failure appears in its lower section with exit/timeout and stderr (stdout fallback); Edit Input restores the submitted argument without running it. Enter explicitly retries. If the owner dismissed/navigated away, completion must not reopen or overwrite the new view. Hiding for any reason clears failure/input; late completion cannot restore it, and deliberate reopening starts clean. Immediate validation errors stay in the field.

## Settings reference

Use a dedicated settings window with two useful sections: **General** and **Commands**. Within Commands, reproduce the supplied settings screenshot's core structure:

- Top search field; `All`, `Apps`, and `Scripts` filters; a `+` control for adding a script or an application outside indexed roots.
- Table/list columns: real app icon and Name, Type, Alias, Hotkey, Enabled. Group scripts and applications where it improves scanning; use alternating/rounded selected rows and native typography/materials.
- Double-click an application’s Hotkey cell to open an inline recording field; a single click selects the row. An assigned shortcut has a visible × control to remove it in both the cell and inspector. Escape closes the field without saving, preserving the prior shortcut (or unassigned state). Focus loss also cancels; Delete explicitly clears.
- Double-click an Alias cell (or inspector alias) to edit. Enter saves, Escape cancels, and × removes an assignment. Focus/window/cell loss cancels unfinished edits; invalid/duplicate aliases retain the draft and show an error. Select an item to edit its enabled status. Script details include name, path, interpreter, argument toggle/placeholder, result handling, timeout, working directory, and optional environment overrides.
- Commands includes Add Folder, Refresh Scripts and a connected-folders disclosure with disconnect controls. Existing command customizations survive scans; disabling hides a managed script. Refresh on startup and explicit request; direct children only.
- Discovered applications are automatically listed. Disabling hides an app from launcher search without uninstalling or deleting it.
- General prominently starts with launch-at-login, then launcher shortcut status, Keep Awake, Caps Lock → F19, application roots, configuration and recent runs.
- Do not add empty AI, account, cloud-sync, organizations, or other unrelated sections from Raycast.

## Script result contract

- Default `discard` mode: run for side effects; the script can invoke `/usr/bin/open` itself.
- Optional `openURL` mode: on exit code zero, stdout must contain one absolute HTTP(S) URL after removing surrounding whitespace. Open it with the default browser using `NSWorkspace`. Do not open output on failure, on timeout, or when output is malformed/multiple URLs.
- Keep stderr separate from stdout. Present exit status and useful failure text without freezing the launcher.
- A command is an explicitly selected local file/executable, not arbitrary shell source entered into the launcher.
- Existing Raycast scripts have not been supplied. Use generic examples; migrate the owner's real Kibana command when available. The folder importer recognizes title and one required text argument; broader Raycast metadata/import compatibility remains outside v1.

## Deferred features

Shortcuts/Kasa, clipboard history, snippets, file search, window management, calculator, AI, plugin marketplace, cloud sync, multiple argument fields, script-specific global shortcuts, arbitrary key-remapping rules, custom layout-switching engine, arbitrary-layout transliteration, automatic updates, and publishing/notarization.

## End-to-end acceptance

1. Command + Space works globally with either Command key, without Accessibility or Input Monitoring. Check with matching Spotlight/Raycast shortcuts released by the owner during a deliberate manual test.
2. Find an installed app by name or fuzzy query, assign an alias through Settings, restart Uficast, and launch via the saved alias.
3. Create script alias `k`, select it with Tab, paste one text value, and run with Enter. Verify the script receives exactly one unchanged argument and a fixture URL opens in the default browser.
4. Run a shell script and an AppleScript; observe useful handling of a missing executable, nonzero exit, invalid URL, and timeout.
5. Enable Caps Lock → F19, assign F19 to the system input-source shortcut, and test repeated switches between the existing two layouts. Confirm the owner's perceived delay is improved; never infer this from a successful remap alone.
6. Restart the app, sleep/wake, and reconnect a keyboard without losing saved settings or unrelated key mappings. Test relogin/autostart when enabled.

## Owner additions and acceptance

- Opening or reopening the app reveals the launcher; the gear button opens Settings. A second process must exit after notifying the first. Use a durable process-held lock rather than an unreliable PID file.
- App shortcuts use physical key code/modifiers; duplicate combinations are rejected regardless of display labels. While recording, Uficast temporarily releases its own registrations and restores them when recording ends.
- Show/hide means activate/unhide a background app, hide an already active app, and launch a closed app. This applies to the application, not individual windows.
- App icons load on a serial background queue as small bitmap data. Completion updates only the matching existing launcher cell; search, selection and scroll position must remain stable.
- Keep Awake uses a native IOPM idle-display-sleep assertion (which also prevents idle system sleep), off on first installation, with indefinite/30-minute/one-hour sessions. Remember the last active/off state locally across exits; timed sessions resume the remaining deadline or stay off if expired. Show a cup icon while active and a `zzz` sleep icon while off (including startup and decaf mode); with the clock enabled, place this state icon left of the calendar in the same button. Also expose state in the tooltip and menu. Release exactly this app's assertion on stop, expiry or quit. The display stays on during idle use while active. Explicit system/lid sleep behavior remains governed by macOS. This owner clarification supersedes the earlier implementation default that allowed the display to sleep.
- Verify actual login after enabling start-at-login, multiple physical keyboards, reconnect/wake, per-app show/hide cycles and a real idle-sleep session. Record observed outcomes separately from fixture tests.

## Keyboard conventions (owner additions)

- Settings opens locally with Cmd+, and the owner's additional Cmd+P (macOS normally uses Cmd+P for printing). Esc closes Settings, except that inline alias/hotkey edits consume the first Esc to cancel; script sheets retain their own Cancel behavior.
- Provide standard menu commands: Cmd+W close window/panel, Cmd+F search (Commands in Settings), Cmd+H hide, Option+Cmd+H hide others, Cmd+M minimize Settings and Cmd+Q quit. Preserve normal text editing, undo/redo and focus navigation. No additional global keyboard registrations or input observation.
- Follow Apple's documented conventions where applicable; a launcher has no document printing/opening/tab system to assign those commands to.

## Day-O calendar (owner addition)

- Developed on `codex/day0-calendar-experiment`, branched from `7ebcf04` after the adjacent chat completed; the owner authorized integration into main on November 18, 2026. The owner's screenshots are visual references. The owner explicitly clarified that the upper menu bar is intended and that the clock itself is Uficast's one button.
- Match Day-O using AppKit's standard `NSDatePicker` in `clockAndCalendar` mode, rather than a custom date grid. Preserve native compact sizing, previous/next month controls, Today, selected-date appearance and light/dark behavior. Reset to today on each menu opening. No event/account integration.
- Center the native calendar with equal outer side margins as in Day-O. Omit keyboard-shortcut hints from the status menu to keep it narrow; the existing application-menu shortcuts remain active. Diagnostics, refresh and shortcut retry are in Settings. Keep Awake uses its existing service through a submenu. Add the Date & Time settings entry shown in the reference.
- General offers Date & Time Format and Show Icon. The calendar icon includes the current day. A zzz/cup indicator for the current Keep Awake state appears to its left in the same button; it stays visible when Show Icon hides the calendar. Implementation defaults: clock enabled, icon shown, format `EEE HH:mm:ss`, Monday-first Gregorian calendar with English labels; users may disable the clock to restore the cup/zzz button. Settings persist in the existing versioned configuration, with legacy files decoding defaults.
- Seconds must follow system-second boundaries, rather than an arbitrary one-second interval starting at app launch. Recalculate the next tick from wall time each time and resynchronize on clock/time-zone changes and wake. Actual side-by-side visual timing remains a manual check.
- The owner authorized read-only examination of installed Day-O for matching its design. No Day-O executable, artwork or other bundled asset is copied into the repository or needed at runtime.
