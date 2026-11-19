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
- In Commands, record an app shortcut, cancel recording with Escape, clear with Delete, and verify duplicate/reserved-chord errors. A background app comes forward, an active app hides, and a closed app launches.
- General starts with the startup checkbox. Check actual Login Items authorization/status and a real relogin after enabling it at the intended stable bundle path.
- For every physical keyboard used, leave macOS Modifier Keys Caps Lock → Caps Lock, enable the Uficast F19 mapping and assign F19 to the input-source shortcut. Test with two keyboards, reconnect and wake; ensure another tool's mappings survive. Quitting Uficast removes only its own mapping.
- Keep Awake starts off. Test indefinite/timed enable, renewal, expiry and stop; confirm the actual power assertion belongs to Uficast. Display/lid/explicit sleep are governed by macOS. Never infer real idle-sleep acceptance from a fixture backend.

## Wrong-layout search

- Search for Chrome with `сркщьу` and Firefox with `ашкуащч`, where installed; test `ntktuhfv` against a Russian-named fixture Телеграм.
- Verify a literal exact alias wins over its converted counterpart, and both beat name matches. Check Commands search too.
- Paste mixed-language text into a script argument and verify it arrives unchanged.

## Later-stage acceptance

Follow [requirements](plan/REQUIREMENTS.md). Caps Lock remapping, login items, opening URLs and real script execution require intentional user actions. Automated core tests use fixtures and temporary directories.
