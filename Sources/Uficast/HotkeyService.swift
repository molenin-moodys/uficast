import AppKit
import Carbon.HIToolbox
import UficastCore

/// Registers only Cmd+Space. Does not observe the keyboard or request privacy grants.
@MainActor
final class HotkeyService {
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var hotkey = LauncherHotkey()
    private let signature: OSType = 0x55464943 // UFIC
    var onToggle: (() -> Void)?
    var onStatusChange: (() -> Void)?
    private(set) var status = "Shortcut is not registered."
    private(set) var lastError: OSStatus = noErr
    var isRunning: Bool { registration != nil }

    func start() {
        stop()
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                Unmanaged<HotkeyService>.fromOpaque(context).takeUnretainedValue().handle(event)
            }
        }
        let installed = InstallEventHandler(GetApplicationEventTarget(), callback, types.count,
                                            &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { fail(installed); return }
        let code = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey),
                                       EventHotKeyID(signature: signature, id: 1),
                                       GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &registration)
        guard code == noErr else { stop(); fail(code); return }
        lastError = noErr
        status = "⌘ Space registered. Disable the matching Spotlight/Raycast shortcut if needed."
        onStatusChange?()
    }

    func stop() {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
        registration = nil
        handler = nil
        hotkey.reset()
    }

    private func fail(_ code: OSStatus) {
        lastError = code
        status = code == eventHotKeyExistsErr
            ? "⌘ Space is already registered by another app. Release it there, then Retry."
            : "Could not register ⌘ Space (error \(code)). Use Open Launcher or Retry."
        onStatusChange?()
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var identity = EventHotKeyID()
        let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &identity)
        guard result == noErr, identity.signature == signature, identity.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) { hotkey.release() }
        else if hotkey.press() { onToggle?() }
        return noErr
    }
}
