# Configurable launcher hotkey, focus-display placement, readable clock

Status: draft, awaiting owner approval. Date: November 19, 2026.

## Intent

1. The owner wants to choose a launcher shortcut other than Cmd+Space.
2. The launcher should open on the display that has focus, not the one under the pointer.
3. The owner cannot read the menu-bar clock on an inactive display, where macOS dims the bar.

## Goals / non-goals / anti-goals

- Goals: the three behaviors above, with Cmd+Space still the default.
- Non-goals: changing system menu-bar dimming (not possible from an app), a second clock window, multi-display Space management.
- Anti-goals: any Accessibility or Input Monitoring request (mandatory project rule); breaking existing config files.

## Approaches considered

- Dimming: (A) turn off "Displays have separate Spaces" in macOS (owner's system change, removes the bar on secondary displays); **(B) draw the clock as our own non-template image with a fixed contrast color — picked by the owner**; (C) a floating clock window (rejected: conflicts with the "single menu-bar button" requirement).
- Hotkey and display: one sensible way each, no real alternatives.

## Design

**1. Launcher hotkey.**
- `Configuration` gets an optional `launcherHotkey: GlobalShortcut?`, read with `decodeIfPresent`. Schema version stays 1. `nil` means Cmd+Space.
- Validation uses the effective launcher shortcut instead of the fixed constant, so an app hotkey cannot equal it. The launcher shortcut itself passes the existing `validate()`.
- `HotkeyService` registers the effective shortcut; its status text uses `display` instead of the hard-coded "⌘ Space".
- General settings get a recorder row with a "Reset to ⌘Space" button. It reuses `ShortcutRecorder`, including the existing "suspend our registrations while recording" behavior. Escape cancels without saving.
- If the new shortcut cannot be registered, show the error and keep the previous value saved.

**2. Focus display.**
- In `show()`, take the frontmost non-Uficast application captured there and find its topmost normal window (layer 0) through `CGWindowListCopyWindowInfo`. Only owner PID and bounds are used; no Screen Recording grant is needed.
- Pick the screen with the largest overlap with that window. A pure function in `UficastCore` does the geometry so it can be unit-tested.
- Fallback when the app has no window or nothing matches: the screen under the pointer, as today.

**3. Clock readability (experiment).**
- Render the clock text, together with the existing icon, into one non-template `NSImage` with an explicit color: light on a dark menu bar, dark on a light one, chosen from the button's effective appearance and re-rendered when it changes.
- Keep the accessibility label and tooltip.
- This may not stop the dimming, because macOS may dim the whole bar. I cannot verify it without a second display, so the owner confirms it on the real setup. If it does not help, revert this part; options A or leaving it as is remain.

## Left to the builder

- File and type naming; the exact layout of the General row.
- Update `REQUIREMENTS.md` (line 45, "display containing the pointer"), `ARCHITECTURE.md`, `PROGRESS.md` and `MANUAL_TESTS.md`.
- Tests: config round-trip of an old file without the field, validation conflicts in both directions, screen-overlap function, offscreen preview of the new clock image.

## Manual checks (not claimed until done)

- Record a new launcher shortcut, press it, relaunch, confirm it persists; reset to Cmd+Space.
- Two displays: focus a window on each, press the shortcut, confirm placement.
- Inactive display: confirm whether the clock is readable.
