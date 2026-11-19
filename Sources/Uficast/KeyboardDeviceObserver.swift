import Foundation
import IOKit

/// Registry lifecycle notifications only. Never opens HID devices or listens to keys.
@MainActor
final class KeyboardDeviceObserver {
    private var port: IONotificationPortRef?
    private var source: CFRunLoopSource?
    private var iterators: [io_iterator_t] = []
    private var debounce: Task<Void, Never>?
    var onChange: (() -> Void)?

    func start() {
        stop()
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        let callback: IOServiceMatchingCallback = { context, iterator in
            drain(iterator)
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<KeyboardDeviceObserver>.fromOpaque(context).takeUnretainedValue().changed()
            }
        }
        for serviceClass in ["IOHIDDevice", "IOHIDEventService"] {
        for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, kind, IOServiceMatching(serviceClass), callback,
                                                          Unmanaged.passUnretained(self).toOpaque(), &iterator)
            if result == KERN_SUCCESS { iterators.append(iterator); drain(iterator) }
        }
        }
    }

    func stop() {
        debounce?.cancel()
        iterators.forEach { IOObjectRelease($0) }
        iterators = []
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { IONotificationPortDestroy(port) }
        source = nil
        port = nil
    }

    private func changed() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.onChange?()
        }
    }
}

private func drain(_ iterator: io_iterator_t) {
    while true {
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return }
        IOObjectRelease(service)
    }
}
