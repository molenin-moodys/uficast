import SwiftUI
import AppKit
import UficastCore

struct ScriptEditor: View {
    @ObservedObject var model: SettingsModel
    @State var script: ScriptCommand
    @State private var environment = "{}"
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Script Command").font(.title2.bold()).padding(20)
            Form {
                TextField("Name", text: $script.name)
                TextField("Alias", text: Binding(get: { script.alias ?? "" }, set: { script.alias = $0.isEmpty ? nil : $0 }))
                HStack {
                    TextField("Script path", text: $script.path)
                    Button("Choose…") { chooseScript() }
                }
                TextField("Interpreter (optional)", text: Binding(get: { script.interpreter ?? "" }, set: { script.interpreter = $0.isEmpty ? nil : $0 }))
                Text("Examples: /bin/zsh, /bin/bash, /usr/bin/osascript. Leave empty to run an executable using its shebang.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Accept one required text argument", isOn: $script.requiresArgument)
                TextField("Argument placeholder", text: $script.argumentPlaceholder).disabled(!script.requiresArgument)
                Picker("Result", selection: $script.resultMode) {
                    Text("Run for side effects").tag(ScriptCommand.ResultMode.discard)
                    Text("Open stdout URL in browser").tag(ScriptCommand.ResultMode.openURL)
                }
                TextField("Timeout (seconds)", value: $script.timeoutSeconds, format: .number)
                TextField("Working directory (optional)", text: Binding(get: { script.workingDirectory ?? "" }, set: { script.workingDirectory = $0.isEmpty ? nil : $0 }))
                Text("Environment overrides (JSON string values)").font(.caption)
                TextEditor(text: $environment).font(.system(.body, design: .monospaced)).frame(height: 80).border(.quaternary)
                Toggle("Enabled", isOn: $script.isEnabled)
            }.formStyle(.grouped).disabled(model.isBusy)
            HStack {
                Text(error.isEmpty ? model.status : error).font(.caption).foregroundStyle(error.isEmpty ? .secondary : Color.red)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(model.isBusy || model.isReadOnly)
            }.padding(16)
        }
        .frame(width: 680, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let data = try? JSONSerialization.data(withJSONObject: script.environment, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) { environment = text }
        }
        .onChange(of: model.saveRevision) { _, _ in
            if model.configuration.scripts.contains(script) { dismiss() }
        }
    }

    private func save() {
        do {
            script.environment = try JSONDecoder().decode([String: String].self, from: Data(environment.utf8))
            var config = model.configuration
            if let index = config.scripts.firstIndex(where: { $0.id == script.id }) {
                if script.sourceDirectory != nil, script.path != config.scripts[index].path {
                    script.sourceDirectory = nil
                    script.id = UUID().uuidString
                }
                config.scripts[index] = script
            }
            else { config.scripts.append(script) }
            _ = try config.validated()
            error = ""
            model.onSave?(config)
        } catch { self.error = error.localizedDescription }
    }

    private func chooseScript() {
        let picker = NSOpenPanel()
        picker.title = "Choose Script"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        script.path = url.path
        if script.name == "New Script" { script.name = url.deletingPathExtension().lastPathComponent }
        switch url.pathExtension.lowercased() {
        case "applescript", "scpt": script.interpreter = "/usr/bin/osascript"
        case "py": script.interpreter = "/usr/bin/python3"
        case "sh": script.interpreter = "/bin/bash"
        case "zsh": script.interpreter = "/bin/zsh"
        default: script.interpreter = nil
        }
    }
}
