import Testing
import UficastCore

@Test func detectsBlockedCapsAcrossMultipleKeyboardProfiles() {
    let normal = ["HIDKeyboardModifierMappingSrc": KeyMapping.capsLock, "HIDKeyboardModifierMappingDst": KeyMapping.capsLock]
    let option = ["HIDKeyboardModifierMappingSrc": KeyMapping.capsLock, "HIDKeyboardModifierMappingDst": UInt64(0x7000000E6)]
    let disabled = ["HIDKeyboardModifierMappingSrc": KeyMapping.capsLock, "HIDKeyboardModifierMappingDst": UInt64(0xFF00000003)]
    let prefix = ModifierMappingDiagnostics.prefix
    #expect(ModifierMappingDiagnostics.conflictingProfiles(in: [
        prefix + "internal": [normal], prefix + "external-a": [option], prefix + "external-b": [disabled],
        "unrelated": [disabled],
    ]) == [prefix + "external-a", prefix + "external-b"])
}
