import AppKit
import UficastCore

@MainActor
final class InstanceCoordinator {
    private let name = Notification.Name("dev.ufian.Uficast.openLauncher")
    private var observer: NSObjectProtocol?
    private var lock: InstanceLock?
    var onReopen: (() -> Void)?

    func becomePrimary() throws -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Uficast/instance.lock")
        lock = try InstanceLock.acquire(at: url)
        guard lock != nil else { return false }
        observer = DistributedNotificationCenter.default().addObserver(forName: name, object: NSUserName(), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onReopen?() }
        }
        return true
    }

    func revealPrimary() {
        DistributedNotificationCenter.default().postNotificationName(name, object: NSUserName(), userInfo: nil, deliverImmediately: true)
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "dev.ufian.Uficast")
        where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            app.activate()
        }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        lock?.release()
        lock = nil
    }
}
