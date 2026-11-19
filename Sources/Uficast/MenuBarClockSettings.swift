import SwiftUI
import UficastCore

struct MenuBarClockSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var format = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Menu Bar Calendar").font(.title2.bold())
            Toggle("Show date and time in the Uficast button", isOn: Binding(
                get: { model.configuration.menuBarClock.isEnabled },
                set: { value in save { $0.isEnabled = value } }))
            Text("Click the Uficast button to browse months. The calendar does not read events or accounts.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Date & Time Format").fontWeight(.medium)
            HStack {
                TextField("EEE HH:mm:ss", text: $format).textFieldStyle(.roundedBorder)
                    .onSubmit { saveFormat() }
                Button("Apply") { saveFormat() }
                    .disabled(format == model.configuration.menuBarClock.dateFormat)
                Button("Reset") { format = MenuBarClockPreferences().dateFormat; saveFormat() }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Preview: \(preview(context.date))").monospacedDigit().foregroundStyle(.secondary)
            }
            Text("EEE = weekday · HH = 24-hour · h = 12-hour · mm = minutes · ss = seconds · a = AM/PM. Quote literal text with single quotes.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show Icon", isOn: Binding(
                get: { model.configuration.menuBarClock.showsIcon },
                set: { value in save { $0.showsIcon = value } }))
                .help("Show a calendar icon with today's date beside the clock.")
        }
        .disabled(model.isBusy || model.isReadOnly)
        .onAppear { format = model.configuration.menuBarClock.dateFormat }
        .onChange(of: model.configuration.menuBarClock.dateFormat) { _, value in format = value }
    }

    private func preview(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = String(format.prefix(128))
        return String(formatter.string(from: date).prefix(100))
    }

    private func save(_ change: (inout MenuBarClockPreferences) -> Void) {
        var config = model.configuration
        change(&config.menuBarClock)
        do { try config.menuBarClock.validate(); model.onSave?(config) }
        catch { model.status = error.localizedDescription }
    }

    private func saveFormat() { save { $0.dateFormat = format } }
}
