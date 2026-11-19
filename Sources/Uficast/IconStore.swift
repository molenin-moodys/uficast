import AppKit
import Combine

@MainActor
final class IconStore: ObservableObject {
    @Published private var revision: UInt = 0
    private var cache: [URL: NSImage] = [:]
    private var cacheOrder: [URL] = []
    private var pending: Set<URL> = []
    private var failed: Set<URL> = []
    private let loader = DispatchQueue(label: "Uficast.icons", qos: .utility)
    private var completions: [URL: [(NSImage?) -> Void]] = [:]

    func icon(for url: URL, onLoad: ((NSImage?) -> Void)? = nil) -> NSImage? {
        if let image = cache[url] { return image }
        if !failed.contains(url), let onLoad { completions[url, default: []].append(onLoad) }
        if !failed.contains(url), pending.insert(url).inserted {
            let loader = self.loader
            Task { [weak self] in
                // Transfer encoded data across actors, never a mutable NSImage.
                let data: Data? = await withCheckedContinuation { continuation in
                    loader.async {
                        let data: Data? = autoreleasepool {
                            let icon = NSWorkspace.shared.icon(forFile: url.path)
                            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
                            NSGraphicsContext.saveGraphicsState()
                            NSGraphicsContext.current = context
                            icon.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64), from: .zero, operation: .copy, fraction: 1)
                            NSGraphicsContext.restoreGraphicsState()
                            return bitmap.representation(using: .png, properties: [:])
                        }
                        continuation.resume(returning: data)
                    }
                }
                guard let self else { return }
                self.pending.remove(url)
                let image = data.flatMap { NSImage(data: $0) }
                if let image {
                    if self.cache.count >= 256, let oldest = self.cacheOrder.first {
                        self.cache.removeValue(forKey: oldest)
                        self.cacheOrder.removeFirst()
                    }
                    self.cache[url] = image
                    self.cacheOrder.append(url)
                } else { self.failed.insert(url) }
                let callbacks = self.completions.removeValue(forKey: url) ?? []
                callbacks.forEach { $0(image) }
                self.revision += 1
            }
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil)
    }
}
