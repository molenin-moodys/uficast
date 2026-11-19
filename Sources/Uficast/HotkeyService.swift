import AppKit
import Carbon.HIToolbox
import UficastCore

/// Carbon global registration only: no keyboard observation or privacy grants.
@MainActor
final class HotkeyService {
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var states: [UInt32: LauncherHotkey] = [:]
    private var appIDs: [UInt32: String] = [:]
    private var appShortcuts: [String: GlobalShortcut] = [:]
    private var launcherShortcut = GlobalShortcut.launcher
    private var aiShortcuts: [AITextAction: GlobalShortcut] = [:]
    /// Carbon IDs: 1 launcher, 2… applications, these for the AI clipboard actions.
    private static let aiIDs: [AITextAction: UInt32] = [.rewrite: 1000, .translate: 1001]
    private let signature: OSType = 0x55464943
    var onToggle: (() -> Void)?
    var onAppToggle: ((String) -> Void)?
    var onAIAction: ((AITextAction) -> Void)?
    var onStatusChange: (() -> Void)?
    private(set) var appErrors: [String: String] = [:]
    private(set) var aiErrors: [AITextAction: String] = [:]
    private(set) var status = "Shortcut is not registered."
    private(set) var lastError: OSStatus = noErr
    var isRunning: Bool { registrations[1] != nil }

    func configure(launcher: GlobalShortcut, ai: [AITextAction: GlobalShortcut], appShortcuts: [String: GlobalShortcut]) {
        guard launcherShortcut != launcher || aiShortcuts != ai || self.appShortcuts != appShortcuts else { return }
        launcherShortcut = launcher
        aiShortcuts = ai
        self.appShortcuts = appShortcuts
        start()
    }

    /// Registers and immediately releases a candidate, so a combination another
    /// app already owns is reported before it replaces the working launcher key.
    func availabilityError(for shortcut: GlobalShortcut) -> OSStatus? {
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: signature, id: UInt32.max), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &reference)
        if let reference { UnregisterEventHotKey(reference) }
        return result == noErr ? nil : result
    }

    func start() {
        stop()
        appErrors = [:]
        aiErrors = [:]
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
        guard installed == noErr else {
            status = "Could not install hotkeys (error \(installed))."
            lastError = installed
            onStatusChange?()
            return
        }
        lastError = register(launcherShortcut, id: 1)
        let name = launcherShortcut.display
        status = lastError == noErr ? "\(name) registered. Release matching Spotlight/Raycast shortcuts if needed."
            : "\(name) unavailable (error \(lastError)). Release it in other apps, then Retry."
        for action in AITextAction.allCases {
            guard let shortcut = aiShortcuts[action], let id = Self.aiIDs[action] else { continue }
            let code = register(shortcut, id: id)
            if code != noErr { aiErrors[action] = "Shortcut unavailable (error \(code)). Release it in other apps, then Retry." }
        }
        for (offset, id) in appShortcuts.keys.sorted().enumerated() {
            let token = UInt32(offset + 2)
            let code = register(appShortcuts[id]!, id: token)
            if code == noErr { appIDs[token] = id }
            else { appErrors[id] = "Shortcut unavailable (error \(code)). Release it in other apps, then Retry." }
        }
        onStatusChange?()
    }

    func stop() {
        registrations.values.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
        registrations = [:]
        states = [:]
        appIDs = [:]
        handler = nil
    }

    private func register(_ shortcut: GlobalShortcut, id: UInt32) -> OSStatus {
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &reference)
        if result == noErr, let reference { registrations[id] = reference; states[id] = LauncherHotkey() }
        return result
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var identity = EventHotKeyID()
        let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &identity)
        guard result == noErr, identity.signature == signature, var state = states[identity.id] else { return OSStatus(eventNotHandledErr) }
        let trigger: Bool
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) { state.release(); trigger = false }
        else { trigger = state.press() }
        states[identity.id] = state
        if trigger {
            if identity.id == 1 { onToggle?() }
            else if let action = Self.aiIDs.first(where: { $0.value == identity.id })?.key { onAIAction?(action) }
            else if let app = appIDs[identity.id] { onAppToggle?(app) }
        }
        return noErr
    }
}
