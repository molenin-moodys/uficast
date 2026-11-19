# AI Text Rewrite and Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite (correct, simple English) and translate (EN↔RU) text from the clipboard or a macOS Service through an owner-editable CLI command, keeping inline formatting, with Enter to insert/copy and Esc to cancel.

**Architecture:** UficastCore gets a stdin-capable process run, an `AITextRunner` that executes the command through `/bin/zsh -lc`, prompt assembly, span-marker encoding/decoding and configuration. The app target gets a rich-text bridge (attributed string ↔ marked runs, pasteboard read/write), a separate result panel with the launcher's look, a coordinator that serves both entry points, Services in Info.plist, two global hotkeys and a General settings section.

**Tech Stack:** Swift 6 / AppKit / SwiftUI settings, Carbon `RegisterEventHotKey`, NSServices, the existing C `UficastProcess` worker, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-19-ai-text-rewrite-translate-design.md`

## Global Constraints

- No Accessibility, Input Monitoring, synthetic keystrokes or keyboard observation.
- Selected text reaches the CLI only through stdin, never argv or shell text.
- Default command: `claude -p --model claude-haiku-5-5 --tools "" --strict-mcp-config --disable-slash-commands --no-session-persistence --setting-sources project,local`.
- Command runs as `/bin/zsh -lc <command>` in `~/Library/Application Support/Uficast/ai-workdir` (created on demand, empty). Timeout 60 s. stdout limit 1 MiB.
- Command validation: non-empty after trimming, no NUL, at most 2,000 characters.
- Services: "Rewrite with Uficast" / "Translate with Uficast", send and return types `public.rtf` and `public.utf8-plain-text`, `NSTimeout` 90000. Service wait deadline 85 s.
- Clipboard read order: RTF, then HTML, then plain text. Read only on an explicit AI hotkey press.
- Exactly one AI request at a time; a new one cancels the old. No automatic retry. Late results never change anything after the panel was hidden.
- Uficast writes no selected text or results to disk or logs.
- Build/test on this toolchain: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`; tests via `scripts/test.sh --build-system native`; app builds into `UFICAST_OUTPUT_ROOT="$PWD/.build/check"`.
- English UI and docs. Never commit personal paths or configuration.

## Review Focus

1. A very large selection (hundreds of KB): stdin writing must not deadlock with a CLI that reads slowly or exits early; the app must not die from SIGPIPE. → Task 1 tests.
2. CLI missing or not logged in (`command not found`, exit 127, stderr only): the panel shows the stderr text, never an empty "result". → Task 2 tests.
3. Text that already contains `<`, `&` or HTML-like tags (an email quoting code): escaping must round-trip exactly and never be mistaken for markers. → Task 3 tests.
4. Esc during "Working…" in a Service request: the Service returns without writing, the process is cancelled, and the late result is ignored. → Task 5 verification.
5. AI hotkey with an empty clipboard or a non-text clipboard (image): "Copy text first." and no CLI run. → Task 5 verification.

---

### Task 1: stdin support in the native worker

**Files:**
- Modify: `Sources/UficastProcess/include/uficast_process.h`, `Sources/UficastProcess/process.c`
- Modify: `Sources/UficastCore/ScriptRunner.swift` (make `NativeRun` internal, add input)
- Test: `Tests/UficastCoreTests/ProcessInputTests.swift`

**Interfaces:**
- Produces (C): `int uf_process_run_input(UFProcess *p, const char *executable, char *const argv[], char *const environment[], const char *directory, double timeout, size_t limit, const uint8_t *input, size_t input_size);` — `uf_process_run` becomes a wrapper passing `NULL, 0`, which keeps `/dev/null` as stdin.
- Produces (Swift, module-internal): `final class NativeRun` with `func execute(executable: String, arguments: [String], environment: [String: String], directory: String, timeout: Double, input: Data? = nil) async throws -> ScriptResult`.
- Produces (public): `LocalProcess.run(executable: String, arguments: [String], input: Data, directory: String = "/", timeout: Double = 5) async throws -> ScriptResult` (test entry point; validates like the existing overload).

- [ ] **Step 1: Write failing tests** in `ProcessInputTests.swift`:
  - `stdinRoundTripsLargeInput`: 2 MiB of repeated `"abc\n"` through `/bin/cat` with limit default 1 MiB → `result.succeeded`, `result.stdoutTruncated == true`, first 1 MiB of stdout equals the first 1 MiB of input.
  - `stdinSmallInputExact`: `"héllo <b> & ünïcode\n"` through `/bin/cat` → stdout bytes equal input bytes.
  - `childThatExitsEarlyDoesNotHangOrCrash`: 4 MiB input to `/usr/bin/true` → returns within 5 s, `exitCode == 0`, test process still alive.
  - `timeoutStillAppliesWithPendingInput`: `/bin/sleep 5` with 1 MiB input and timeout 0.5 → `termination == .timedOut`.
- [ ] **Step 2: Run** `SDKROOT=… scripts/test.sh --build-system native --filter ProcessInputTests` → FAIL (no `input:` overload).
- [ ] **Step 3: Implement** in `process.c`: when `input` is non-NULL, create a third pipe, dup2 its read end to stdin instead of `/dev/null`, close it in the parent, set the write end `O_NONBLOCK` and `F_SETNOSIGPIPE`. Add it to the existing poll loop with `POLLOUT`; write up to 16 KiB per readiness; on `EPIPE`/`EBADF` or when all bytes are written, close it. A zero-length input closes it immediately. Close it on stop/timeout too. Thread `input` through `NativeRun.execute` and the new `LocalProcess.run`.
- [ ] **Step 4: Run** the filter again → PASS; then the full suite → all pass (existing script tests unchanged).
- [ ] **Step 5: Commit** `feat(process): optional stdin input for the native worker`.

### Task 2: AI text core — preferences, prompt, runner

**Files:**
- Create: `Sources/UficastCore/AITextPreferences.swift`, `Sources/UficastCore/AITextPrompt.swift`, `Sources/UficastCore/AITextRunner.swift`
- Modify: `Sources/UficastCore/Configuration.swift`
- Test: `Tests/UficastCoreTests/AITextCoreTests.swift`

**Interfaces:**
- Consumes: `NativeRun.execute(…, input:)` from Task 1.
- Produces:
  - `public enum AITextAction: String, Codable, CaseIterable, Sendable { case rewrite, translate }` with `public var title: String` ("Rewrite", "Translate").
  - `public struct AITextPreferences: Codable, Equatable, Sendable { public static let defaultCommand: String; public var command: String; public var rewriteHotkey: GlobalShortcut?; public var translateHotkey: GlobalShortcut?; public func hotkey(for: AITextAction) -> GlobalShortcut?; public func validate() throws }` — every field `decodeIfPresent` with defaults.
  - `Configuration.aiText: AITextPreferences` (CodingKey `aiText`, decodeIfPresent). `validated()` calls `aiText.validate()` and reserves both AI hotkeys in the same signature set as the launcher and enabled app hotkeys (any duplicate → `ConfigError.invalid`).
  - `public enum AITextPrompt { public static func build(action: AITextAction, text: String, hasMarkers: Bool) -> String; public static func clean(_ output: String) -> String }`.
  - `public protocol AITextRunning: Sendable { func run(command: String, prompt: String, timeout: Double) async throws -> String; func cancel() async }`.
  - `public actor AITextRunner: AITextRunning { public init(workingDirectory: URL) }`.
  - `public enum AITextError: Error, LocalizedError, Equatable { case emptyOutput, outputTooLong, failed(String), cancelled }`.

- [ ] **Step 1: Write failing tests** in `AITextCoreTests.swift`:
  - `legacyConfigGetsDefaultAIText`: decode a schema-1 JSON without `aiText` → `config.aiText.command == AITextPreferences.defaultCommand`, both hotkeys nil.
  - `aiCommandValidation`: `"   "`, a string with `"\0"`, and 2,001 characters each make `validated()` throw; 2,000 characters pass.
  - `aiHotkeysConflictWithLauncherAppsAndEachOther`: rewrite hotkey == effective launcher → throws; rewrite == translate → throws; rewrite == an enabled app's hotkey → throws; same with the app disabled → passes.
  - `promptCarriesInstructionsAndText`: `build(.rewrite, text: "we was here", hasMarkers: false)` contains `"<text>\nwe was here\n</text>"` and `"simple English"` and does not mention markers; `build(.translate, …, hasMarkers: true)` contains `"Russian"`, `"English"` and `"<s1>"` (the marker rule).
  - `cleanStripsEchoedTagsAndWhitespace`: `clean("\n<text>\nHello\n</text>\n") == "Hello"`; `clean("  Hi there \n") == "Hi there"`; `clean("<text>only open") == "<text>only open"`.
  - `runnerReturnsStdoutTrimmed`: `AITextRunner(workingDirectory: temp).run(command: "cat", prompt: "Hello\n", timeout: 5) == "Hello"`.
  - `runnerReportsMissingCLIWithStderr`: command `"uficast-no-such-cli-xyz"` → throws `.failed(message)` where `message` contains `"not found"`.
  - `runnerRejectsEmptyOutput`: command `"cat >/dev/null"` → throws `.emptyOutput`.
  - `runnerCancel`: start `"sleep 5"`, call `cancel()` after 0.2 s → throws `.cancelled` within 2 s.
  - `aiHotkeysRoundTrip`: a config with both AI hotkeys and a custom command encodes and decodes equal.
  - `textNeverEntersShellText`: prompt `"$(touch /tmp/uficast-injected); \"'"` with command `"cat"` → output equals the prompt and `/tmp/uficast-injected` does not exist.
- [ ] **Step 2: Run** `--filter AITextCoreTests` → FAIL (types missing).
- [ ] **Step 3: Implement.** Prompt wording follows the spec's rewrite/translate instructions. With `hasMarkers`, add: keep every `<sN>`/`</sN>` pair around the words that carry that style; markers may move but must not be added, renamed, nested or removed; `&lt;`, `&gt;`, `&amp;` are literal characters. Always end with "Output only the result, without the <text> tags." `clean` trims, then removes a leading `<text>` plus trailing `</text>` only when both are present. Runner: create the working directory with 0700, run `/bin/zsh` `["-lc", command]` with the inherited environment, `input: Data(prompt.utf8)` and timeout. Truncated stdout → `.outputTooLong`; cancelled → `.cancelled`; timed out → `.failed("Timed out after 60 s.")` (use the actual timeout); non-zero exit → `.failed(result.failureDescription)`; trimmed empty stdout → `.emptyOutput`. One run at a time: `cancel()` cancels the current `NativeRun`.
- [ ] **Step 4: Run** the filter, then the full suite → PASS.
- [ ] **Step 5: Commit** `feat(core): AI text preferences, prompt and command runner`.

### Task 3: span markers

**Files:**
- Create: `Sources/UficastCore/SpanMarkup.swift`
- Test: `Tests/UficastCoreTests/SpanMarkupTests.swift`

**Interfaces:**
- Produces: `public struct StyledSegment: Equatable, Sendable { public var text: String; public var style: Int? }` (`nil` = base style, otherwise a 0-based index into the caller's style table) and `public enum SpanMarkup { public static func encode(_ segments: [StyledSegment]) -> (text: String, hasMarkers: Bool); public static func decode(_ output: String, styleCount: Int) -> [StyledSegment]? }`.

Rules:
- Marker for style index `i` is `<s{i+1}>…</s{i+1}>`.
- With no styled segment, `encode` returns the concatenated text unescaped and `hasMarkers == false`. `decode(_, styleCount: 0)` returns one base segment with the output unchanged.
- With markers, `encode` escapes `&`, `<` and `>` in segment text as `&amp;`, `&lt;` and `&gt;`.
- `decode` with `styleCount > 0` is strict. It returns nil for an unknown number, a nested or unbalanced marker, an unclosed marker at the end, or any other `<`. It unescapes the three entities and leaves any other `&` literal.
- `decode` merges adjacent segments with equal style and drops empty segments.

- [ ] **Step 1: Write failing tests:**
  - `plainSegmentsStayUnescaped`: `encode([.init(text: "a < b & c", style: nil)]) == ("a < b & c", false)`; `decode("x < y", styleCount: 0) == [.init(text: "x < y", style: nil)]`.
  - `encodeWrapsAndEscapes`: segments `["Use ", "bold"(0), " & ", "<link>"(1)]` → `"Use <s1>bold</s1> &amp; <s2>&lt;link&gt;</s2>"`, `hasMarkers == true`.
  - `roundTripRestoresStyles`: `decode(encode(x).text, styleCount: 2) == x` for the segments above.
  - `movedMarkersAreAccepted`: `decode("<s1>Please</s1> check <s2>it</s2>", styleCount: 2) == [("Please",0), (" check ",nil), ("it",1)]`.
  - `brokenMarkersFallBack`: each of `"<s3>x</s3>"` (count 2), `"<s1><s2>x</s2></s1>"`, `"<s1>x"`, `"x</s1>"`, `"<b>x</b>"` → nil.
  - `entitiesAndStrayAmpersand`: `decode("A &amp; B &lt;3 & co", styleCount: 1) == [("A & B <3 & co", nil)]`.
- [ ] **Step 2: Run** `--filter SpanMarkupTests` → FAIL.
- [ ] **Step 3: Implement** a single left-to-right scanner. Use no regex for decoding, so error positions stay strict.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(core): span markers for keeping inline formatting`.

### Task 4: rich-text bridge and result panel

**Files:**
- Create: `Sources/Uficast/RichTextBridge.swift`, `Sources/Uficast/AITextPanelController.swift`
- Modify: `Sources/Uficast/LauncherPanelController.swift` (make `targetScreen(for:)` `static func` internal so both panels place themselves identically)

**Interfaces:**
- Consumes: `StyledSegment`, `SpanMarkup` (Task 3), `AITextAction` (Task 2).
- Produces:
  - `struct RichText { var segments: [StyledSegment]; var styles: [[NSAttributedString.Key: Any]]; var base: [NSAttributedString.Key: Any]; var isRich: Bool }`
  - `enum RichTextBridge { static func read(_ pasteboard: NSPasteboard) -> NSAttributedString?; static func isRich(_ pasteboard: NSPasteboard) -> Bool; static func split(_ text: NSAttributedString, isRich: Bool) -> RichText; static func join(_ segments: [StyledSegment], from source: RichText) -> NSAttributedString; static func write(_ text: NSAttributedString, rich: Bool, to pasteboard: NSPasteboard) }`
    - Base style: the attributes at index 0. A run equal to the base becomes `nil`. Equal attribute sets share one style index.
    - `write` clears the pasteboard, writes RTF when `rich`, and always writes plain text.
    - `read` returns nil when the pasteboard has no RTF, HTML or non-empty plain text.
  - `@MainActor final class AITextPanelController: NSObject` with:
    - `enum Mode { case replace, copy }`
    - `var onConfirm: ((NSAttributedString) -> Void)?`, `var onCancel: (() -> Void)?`, `var onRetry: (() -> Void)?`
    - `func showWorking(action: AITextAction, mode: Mode)`, `func showResult(_ text: NSAttributedString, note: String?)`, `func showFailure(_ message: String)`, `func showMessage(_ message: String)`, `func switchToCopyMode(note: String)`, `func dismiss()`, `var isVisible: Bool { get }`
    - `func performConfirm()`, `func performCancel()`: what Enter and Esc call; used by the verification too.
  - Panel behavior:
    - Borderless non-activating panel with the launcher's material and corner radius. Placed with `LauncherPanelController.targetScreen(for:)`.
    - Contents: a token with the action title, a read-only selectable `NSTextView` showing attributed text, and a hint line.
    - Hints: replace mode "↩ Replace · Esc Cancel"; copy mode "↩ Copy · Esc Cancel"; working "Working… · Esc Cancel"; failure "↩ Retry · Esc Close"; message "Esc Close".
    - Enter on a result calls `onConfirm`, on a failure calls `onRetry`, and does nothing while working or for a message.
    - Esc, an outside click or losing key calls `onCancel` once, then hides.

- [ ] **Step 1: Write the native check `AITextVerification.richTextRoundTrip()`** in `Sources/Uficast/AITextVerification.swift`, run by the flag `--verify-ai-text`. Wire the flag in `Main.swift`, following `--verify-menu-clock`. Checks:
  - "Please **review** the [file](https://example.com)" splits into 2 styles.
  - `join(decode(encode(segments)))` keeps the bold font trait and the `.link` value.
  - Writing to a uniquely named private pasteboard puts RTF and plain types there, and `read` returns an equal string.
  - A plain-only pasteboard gives `isRich == false`.
  - The panel shows `performConfirm()` → `onConfirm` once, `performCancel()` → `onCancel` once, and the hints for each mode.
- [ ] **Step 2: Build and run** `.build/check/Uficast.app/Contents/MacOS/Uficast --verify-ai-text` → FAIL (types missing / check not passing).
- [ ] **Step 3: Implement** the bridge and the panel.
- [ ] **Step 4: Run** `--verify-ai-text`, `--verify-script-feedback` and `--verify-native-icons` → PASS.
- [ ] **Step 5: Commit** `feat(app): rich-text bridge and AI result panel`.

### Task 5: coordinator — clipboard and Services entry points

**Files:**
- Create: `Sources/Uficast/AITextCoordinator.swift`
- Modify: `Resources/Info.plist` (NSServices), `Sources/Uficast/AITextVerification.swift`

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces: `@MainActor final class AITextCoordinator: NSObject` with:
  - `init(panel: AITextPanelController, runner: AITextRunning, general: NSPasteboard = .general, serviceDeadline: TimeInterval = 85, timeout: Double = 60)`
  - `var command: String`
  - `func runFromClipboard(_ action: AITextAction)`
  - `@objc func rewriteText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>)`
  - `@objc func translateText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>)`
- Info.plist entries: `NSMenuItem.default` "Rewrite with Uficast" / "Translate with Uficast", `NSMessage` `rewriteText` / `translateText`, send and return types `public.rtf` + `public.utf8-plain-text`, `NSTimeout` `90000`, empty `NSRequiredContext` dict.

Behavior:
- Each request gets a UUID. Completion for any other UUID is ignored.
- Starting a request cancels the runner's current run.
- Building and finishing a request:
  - Split the source with the bridge, encode with `SpanMarkup` and build the prompt.
  - Run, `clean`, then decode with the style count. If decoding returns nil, use the base-style fallback (one base segment holding the cleaned text, with marker tags removed) and the note "Formatting could not be kept."
- Clipboard entry point:
  - If `RichTextBridge.read(general)` is nil or empty, call `showMessage("Copy text first.")`.
  - Otherwise use copy mode. Confirm writes to `general` and hides the panel.
- Service entry point (both actions):
  - Read the service pasteboard and start the request in replace mode.
  - Run a nested event loop until a decision or the deadline: `NSApp.nextEvent(matching: .any, until: now + 0.05, inMode: .default, dequeue: true)` followed by `sendEvent`.
  - Confirm writes to the service pasteboard and to `general`, then returns. The bridge writes RTF only when the source was rich.
  - Cancel returns without writing anything.
  - At the deadline:
    - If a result is shown, call `switchToCopyMode(note: "Time ran out for replacing.")`. A later confirm writes only to `general`.
    - If the request is still working, it continues in copy mode.
    - The handler returns without writing.
- Failure shows the error's `localizedDescription`. `onRetry` re-runs the same request under a new UUID. `onCancel` cancels the runner.

- [ ] **Step 1: Extend `--verify-ai-text`** with a fake `AITextRunning`. The fake returns scripted results after a delay and records cancel calls. Use private pasteboards and `serviceDeadline` 0.5. Checks:
  - Empty clipboard: message shown and the runner is never called.
  - A clipboard image only: message shown and the runner is never called.
  - Clipboard rewrite: confirm puts the result on `general`.
  - Cancel during working: the runner is cancelled, and the late result neither appears nor writes.
  - Failure, then retry: the runner is called twice and the second result is shown.
  - Service with a rich source: confirm writes RTF and plain to the service pasteboard and to `general`. The restored bold is present.
  - Service cancel: the service pasteboard is unchanged.
  - Service deadline with the result shown: the handler returns within 1 s without writing, the panel is in copy mode, and a later confirm writes only to `general`.
  - Broken markers from the fake: the fallback note appears, and plain text without `<s1>` is written.
- [ ] **Step 2: Run** `--verify-ai-text` → FAIL.
- [ ] **Step 3: Implement** the coordinator and the Info.plist entries.
- [ ] **Step 4: Run** `--verify-ai-text` → PASS. Run `plutil -lint Resources/Info.plist` → OK.
- [ ] **Step 5: Commit** `feat(app): AI text coordinator with clipboard and Services entry points`.

### Task 6: hotkeys, settings and wiring

**Files:**
- Modify: `Sources/Uficast/HotkeyService.swift`, `Sources/Uficast/AppController.swift`, `Sources/Uficast/SettingsWindowController.swift`, `Sources/Uficast/ViewPreview.swift` (if a fixture default is needed)

**Interfaces:**
- Consumes: `AITextCoordinator` (Task 5), `Configuration.aiText` (Task 2).
- Produces:
  - `HotkeyService.configure(launcher: GlobalShortcut, ai: [AITextAction: GlobalShortcut], appShortcuts: [String: GlobalShortcut])` with Carbon IDs 1000 (rewrite) and 1001 (translate).
  - `var onAIAction: ((AITextAction) -> Void)?` and `private(set) var aiErrors: [AITextAction: String]`.
  - `SettingsModel.onSetAICommand: ((String) -> Void)?`, `onSetAIHotkey: ((AITextAction, GlobalShortcut?) -> Void)?` and `@Published var aiHotkeyErrors: [AITextAction: String]`.
- AppController:
  - Owns `AITextCoordinator(panel:runner: AITextRunner(workingDirectory: …/ai-workdir))`.
  - Sets `NSApp.servicesProvider = coordinator` and calls `NSUpdateDynamicServices()` at launch.
  - `applyConfiguration` sets `coordinator.command` and passes the AI hotkeys.
  - `setAIHotkey` mirrors `setLauncherHotkey`: validate, probe with `availabilityError(for:)`, then save.
  - `setAICommand` trims, validates and saves.
  - Hides the launcher when the AI panel shows.
- General → "AI Text" section, after Launcher:
  - Command: monospaced `TextField` with Apply (enabled when the draft differs) and "Reset to Default".
  - Two recorders: "Rewrite from clipboard" and "Translate from clipboard", each with × removal, plus a red error line from `aiHotkeyErrors`.
  - Caption: "Services: select text, then use “Rewrite with Uficast” or “Translate with Uficast”. Assign their shortcuts in Keyboard Shortcuts → Services.", with a "Keyboard Shortcuts…" button. The button reuses the existing URL.
  - Caption: "The text is sent to the program the command runs (Anthropic for claude). Uficast stores no text; the program may keep data under its own settings."

- [ ] **Step 1: Implement** the wiring and the settings section. (Configuration round trip is already pinned in Task 2; this task is verified by the build, the native checks and the preview.)
- [ ] **Step 2: Verify:**
  - The full test suite passes.
  - The release build into `.build/check` passes with strict signature.
  - All existing native checks pass, plus `--verify-ai-text`.
  - `--preview-settings /tmp/uficast-preview/general-ai.png --general`, viewed visually, shows the AI Text section in light mode. Scroll position is not guaranteed; enlarge the preview window or move the section if it is not visible.
  - `plutil -p .build/check/Uficast.app/Contents/Info.plist` shows both NSServices.
- [ ] **Step 3: Commit** `feat: AI text hotkeys, settings and Services registration`.

### Task 7: docs and handoff

**Files:**
- Modify: `docs/plan/REQUIREMENTS.md` (owner additions: AI text, explicit clipboard read on the AI hotkey as an exception to "no automatic clipboard reads"), `docs/plan/ARCHITECTURE.md` (stdin worker, runner, markers, panel, Services, nested event loop), `docs/plan/IMPLEMENTATION_PLAN.md` (Stage 6n), `docs/plan/PROGRESS.md` (actual checks, unverified items, exact next step), `docs/MANUAL_TESTS.md` (items from the spec's Manual checks), `README.md` (feature line plus a short "AI text" section with the default command and the privacy note)

- [ ] **Step 1: Update the docs.** Record the separate result panel (instead of a launcher mode) as a builder decision with its reason: it keeps the launcher's run/stale state separate. Record that the Services nested loop and real-app replacement are unverified until the owner tests them.
- [ ] **Step 2: Run** `git diff --check` and `grep -rn "/Users/" docs README.md` → no new personal paths.
- [ ] **Step 3: Commit** `docs: record Stage 6n AI text rewrite and translation`.
