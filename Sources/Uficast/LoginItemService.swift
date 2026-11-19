import ServiceManagement

@MainActor
enum LoginItemService {
    static func status() -> (registered: Bool, message: String) {
        switch SMAppService.mainApp.status {
        case .enabled: (true, "Start at login is enabled.")
        case .requiresApproval: (true, "Registration is waiting for your approval in Login Items.")
        case .notRegistered: (false, "Start at login is disabled.")
        case .notFound: (false, "The application bundle could not be found by macOS.")
        @unknown default: (false, "Login-item status is unavailable.")
        }
    }

    static func setEnabled(_ enabled: Bool) async throws {
        if enabled { try SMAppService.mainApp.register() }
        else if status().registered { try await SMAppService.mainApp.unregister() }
    }

    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
