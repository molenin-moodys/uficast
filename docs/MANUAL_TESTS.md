# Desktop verification

All items are pending unless a dated result is recorded in PROGRESS. No Accessibility or Input Monitoring grants are allowed/required by this app.

## Launcher and focus

- Build with `scripts/build.sh`, launch `dist/Uficast.app`, and find its menu bar icon. Confirm Open Launcher, Settings, registration status, Retry and Quit.
- Open from the menu, type/paste, use Cmd+A/C/X/V/Z and Shift+Cmd+Z, then Escape. No keyboard permission prompt should appear.
- Release matching Spotlight/Raycast shortcuts yourself for this test. Automation must not change these settings.
- Cmd+Space toggles once using either Command key. Holding Space must not repeatedly toggle or insert spaces in the previous app.
- Test both Command keys, extra modifiers, releasing Command before Space, retry, sleep/wake, fullscreen and multiple monitors when available.
- Escape and outside clicks dismiss; cancellation restores prior focus when appropriate. Opening a destination must let it take focus.
- Record actual Secure Input behavior and known limitations; do not bypass system protection.

## Added features

- Opening shows the launcher immediately; reopening while it is running reveals the same process. Click the footer gear to open Settings.
- Observe icons loading in the launcher and Settings without changing selection/scroll or flashing placeholders repeatedly. The offscreen --verify-native-icons regression check covers loaded bitmaps with unchanged row geometry and scroll position.
- In Commands, single-click an app Hotkey cell: it only selects. Double-click the current shortcut or Add Hotkey: an inline recording field opens. Press a bare letter then Escape: no configuration save occurs and the previous shortcut reappears. Repeat on an unassigned app; click outside/change section/close Settings while recording and verify global shortcuts are restored. Record a valid combination, remove with the adjacent × (also in Show / Hide), clear with Delete, and verify duplicate/reserved-chord errors. A background app comes forward, an active app hides, and a closed app launches.
- General starts with the startup checkbox. Check actual Login Items authorization/status and a real relogin after enabling it at the intended stable bundle path.
- For every physical keyboard used, leave macOS Modifier Keys Caps Lock → Caps Lock, enable the Uficast F19 mapping and assign F19 to the input-source shortcut. Test with two keyboards, reconnect and wake; ensure another tool's mappings survive. Quitting Uficast removes only its own mapping.
- Keep Awake starts off. Test indefinite/timed enable, renewal, expiry and stop; confirm the actual power assertion belongs to Uficast. Display/lid/explicit sleep are governed by macOS. Never infer real idle-sleep acceptance from a fixture backend.

## Wrong-layout search

- Search for Chrome with `сркщьу` and Firefox with `ашкуащч`, where installed; test `ntktuhfv` against a Russian-named fixture Телеграм.
- Verify a literal exact alias wins over its converted counterpart, and both beat name matches. Check Commands search too.
- Paste mixed-language text into a script argument and verify it arrives unchanged.

## Later-stage acceptance

Follow [requirements](plan/REQUIREMENTS.md). Caps Lock remapping, login items, opening URLs and real script execution require intentional user actions. Automated core tests use fixtures and temporary directories.

## Built-in power commands

- Search caffeine/cafe and decaffeine/decafe; verify Command labels and cup icons. Try cfn/dcfn and Russian physical-key input сфау/вусфау.
- During an owner-initiated power test, run cafe and confirm the menu/Settings state changes to indefinite Keep Awake; repeat without creating extra assertions. Run decafe and confirm that assertion is released. Do not execute a found result just to test search.
- If a user app/script alias is cafe, it remains the preferred alias match; caffeine remains available by full name.

## Script folders

- In Commands, Add Folder (or + → Add Script Folder) opens a directory-only picker. Cancel makes no changes. Connect a fixture directory containing a shell script with a Raycast title and one text argument; it appears immediately and opens argument mode with the expected placeholder. Adding never executes it.
- Refresh after adding/removing files; verify no duplicate commands and retained aliases/enabled/editor options. Restart to verify saved folder discovery. Hidden files and subfolders are skipped.
- An unavailable root reports status and retains records; reconnect/refresh recovers it. Unsupported argument declarations show notices without silently creating a no-argument command.
- Disable a managed script to hide it. Disconnect a folder: its managed commands disappear, manual entries remain and every source file stays intact. Editing a managed path detaches that command.
- Never include private scripts, internal URLs, home paths or real configuration in repository fixtures/screenshots. Test actual private script execution/browser behavior only during an owner-initiated run.

## Alias editing and failed input correction

- Single-click an Alias cell to select its row; double-click to edit. Type a change then Escape: the assigned or empty value remains unchanged. Enter saves exactly once; duplicate/whitespace aliases keep the draft open with an error. Click × to remove. Repeat for apps, scripts and the inspector. Focus loss, section/filter/window changes and reused rows must not save unfinished input.
- In argument mode, compare light/dark and empty/filled states: no opaque white box, matching placeholder/text leading edge and readable selection/caret.
- Run an intentional generic failure with one argument. The launcher stays open during the run and shows the bounded error below. Verify stdout-only failure text too. Edit Input restores spaces/Unicode/newlines exactly and does not run; Enter explicitly retries. Success closes the panel.
- Dismiss/navigate before a slow failure finishes: no reopen or replacement of newer input. Deliberate reopen can offer the last failure and Edit Input. Verify concurrent old completions do not replace the latest run's status. Cancellation/quit must not open a URL.
- Native --verify-alias-editor and --verify-script-feedback cover fixture behavior, not private scripts or physical paste/input acceptance.
