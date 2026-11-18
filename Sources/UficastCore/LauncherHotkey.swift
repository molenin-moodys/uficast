/// Debounces Carbon hotkey-pressed notifications until the matching release.
public struct LauncherHotkey: Sendable {
    private var isPressed = false

    public init() {}

    public mutating func press() -> Bool {
        guard !isPressed else { return false }
        isPressed = true
        return true
    }

    public mutating func release() { isPressed = false }
    public mutating func reset() { isPressed = false }
}
