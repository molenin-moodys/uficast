import AppKit
import SwiftUI
import UficastCore

/// General → AI Text: the editable command, clipboard shortcuts and Services guidance.
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
            Text("Services: select text, then use “Rewrite with Uficast” or “Translate with Uficast”; ↩ replaces the selection. Assign their shortcuts in Keyboard Shortcuts → Services.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Keyboard Shortcuts…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts") { NSWorkspace.shared.open(url) }
            }
            Text("The text is sent to the program the command runs (Anthropic for claude). Uficast stores no text; the program may keep data under its own settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { draft = model.configuration.aiText.command }
        .onChange(of: model.configuration.aiText.command) { _, command in draft = command }
    }
}
