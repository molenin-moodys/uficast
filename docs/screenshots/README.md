# README screenshots

These PNGs capture actual Uficast AppKit/SwiftUI views rendered offscreen with public demonstration data, not the owner's configuration or desktop.

- `launcher.png`: Calculator, Calendar, Notes, Safari and Terminal, with example aliases.
- `commands.png`: the same apps plus a generic script; the Terminal shortcut is an example only.
- `error.png`: generic fixture failure and Edit Input action; no actual script ran for this capture.
- `argument.png`: dark appearance with a generic script and the literal argument `release notes`.

Fixtures are defined in `Sources/Uficast/ViewPreview.swift`. Only the fixed standard-app paths are used for icons; there is no catalog discovery, personal configuration load, script execution, hotkey registration or system setting change. Preview state does not describe actual startup, remapping or power settings.

From the repository root:

```sh
scripts/build.sh
scripts/screenshots.sh
```

Quit before replacing a running bundle, or build with `UFICAST_OUTPUT_ROOT` and pass that `.app` path to the screenshot script. Visually inspect every regenerated image before committing it.
