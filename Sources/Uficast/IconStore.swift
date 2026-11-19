import AppKit

@MainActor
final class IconStore {
    private let cache = NSCache<NSURL, NSImage>()
    private var pending: Set<URL> = []
    private var failed: Set<URL> = []
    var onLoad: (() -> Void)?

    init() { cache.countLimit = 200 }

    func icon(for url: URL) -> NSImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        if !failed.contains(url), pending.insert(url).inserted {
            Task { [weak self] in
                // Transfer encoded data across actors, never a mutable NSImage.
                let data = await Task.detached(priority: .utility) {
                    NSWorkspace.shared.icon(forFile: url.path).tiffRepresentation
                }.value
                guard let self else { return }
                self.pending.remove(url)
                if let data, let image = NSImage(data: data) { self.cache.setObject(image, forKey: url as NSURL) }
                else { self.failed.insert(url) }
                self.onLoad?()
            }
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil)
    }
}
