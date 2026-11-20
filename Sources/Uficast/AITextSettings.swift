import AppKit
import SwiftUI
import UficastCore

/// General → AI Text: the editable command, clipboard shortcuts and the Shortcuts that open requests here.
struct AITextSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Text").font(.title2.bold())
            Text("Command").fontWeight(.medium)
            HStack {
                TextField("Command", text: $draft).font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder)
                    .onSubmit { model.onSetAICommand?(draft) }
                Button("Apply") { model.onSetAICommand?(draft) }
                    .disabled(draft == model.configuration.aiText.command)
                Button("Reset to Default") { model.onSetAICommand?(AITextPreferences.defaultCommand) }
                    .disabled(model.configuration.aiText.command == AITextPreferences.defaultCommand)
            }.disabled(model.isBusy || model.isReadOnly)
            Text("The command gets the prompt on stdin and must print only the answer, for example claude -p or codex. It runs in your login shell; change the model or the program here.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(AITextAction.allCases, id: \.self) { action in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(action.title) from clipboard").frame(width: 190, alignment: .leading)
                        ShortcutRecorder(shortcut: model.configuration.aiText.hotkey(for: action),
                            accessibilityName: "Record \(action.title.lowercased()) from clipboard shortcut",
                            onCapture: { model.onSetAIHotkey?(action, $0) },
                            onBegin: { model.onBeginShortcutRecording?() },
                            onEnd: { model.onEndShortcutRecording?() })
                            .frame(width: 180)
                        if model.configuration.aiText.hotkey(for: action) != nil {
                            Button { model.onSetAIHotkey?(action, nil) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove shortcut")
                            .accessibilityLabel("Remove \(action.title.lowercased()) from clipboard shortcut")
                        }
                    }
                    if let error = model.aiHotkeyErrors[action] { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }.disabled(model.isBusy || model.isReadOnly)
            Text("Copy text, press the shortcut, check the result, then ↩ copies it for pasting. Esc cancels.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Shortcuts").fontWeight(.medium)
            HStack {
                ForEach(AITextAction.allCases, id: \.self) { action in
                    Button("Create \(action.title) Shortcut") { model.onCreateShortcut?(action) }
                }
            }
            Text("Opens a new shortcut in the Shortcuts app and copies the script for it; follow the steps below. The shortcut uses the selected text where the app offers it, otherwise the clipboard, and shows the result here; ↩ copies it.")
                .font(.caption).foregroundStyle(.secondary)
            if let action = model.shortcutGuide { guide(action) }
            Text("The text is sent to the program the command runs (Anthropic for claude). Uficast stores no text; the program may keep data under its own settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { draft = model.configuration.aiText.command }
        .onChange(of: model.configuration.aiText.command) { _, command in draft = command }
    }

    /// Steps for building the shortcut by hand, since Shortcuts refuses to import unsigned files.
    private func guide(_ action: AITextAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Steps for “\(ShortcutGuide.shortcutName(for: action))”").fontWeight(.medium)
            ForEach(Array(ShortcutGuide.steps(for: action).enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)").font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Text(ShortcutGuide.script(for: action))
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button("Copy Script") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ShortcutGuide.script(for: action), forType: .string)
                }
                Button("Hide Steps") { model.shortcutGuide = nil }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
