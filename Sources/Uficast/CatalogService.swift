import AppKit
import UficastCore

@MainActor
final class CatalogService {
    private(set) var entries: [LauncherEntry] = []
    private(set) var unavailableRoots: [URL] = []
    private(set) var isRefreshing = false
    var roots = ApplicationCatalog.defaultRoots
    var onChange: (() -> Void)?
    private var refreshTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var lastRefresh = Date.distantPast

    func refreshIfStale() {
        if Date().timeIntervalSince(lastRefresh) > 30 { refresh() }
    }

    func refresh() {
        refreshTask?.cancel()
        isRefreshing = true
        onChange?()
        let roots = roots
        refreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) { ApplicationCatalog.discover(roots: roots) }.value
            guard !Task.isCancelled, let self else { return }
            self.entries = snapshot.entries
            self.unavailableRoots = snapshot.unavailableRoots
            self.isRefreshing = false
            self.lastRefresh = Date()
            self.watchRoots()
            self.onChange?()
        }
    }

    private func watchRoots() {
        watchers.forEach { $0.cancel() }
        watchers = roots.compactMap { root in
            let descriptor = open(root.path, O_EVTONLY)
            guard descriptor >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.scheduleRefresh() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            return source
        }
    }

    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            self?.refresh()
        }
    }
}
