import Foundation

/// A `.shortcut` file that Shortcuts can import: "Rewrite/Translate with Uficast". It is a
/// Quick Action that takes text (the selection where the app offers it through Services),
/// falls back to the clipboard when there is none, URL-encodes it and opens the matching
/// `uficast://` link. The file format is undocumented; this follows files written by
/// Shortcuts and compilers such as Cherri.
public struct ShortcutFile: Sendable {
    public var fileName: String
    public var data: Data?

    public static func aiText(_ action: AITextAction) -> ShortcutFile {
        let encodeID = UUID().uuidString
        let linkID = UUID().uuidString
        let prefix = AITextURL.prefix(for: action)
        let object = "\u{FFFC}"

        func text(_ string: String, attachments: [String: [String: Any]]) -> [String: Any] {
            ["Value": ["string": string, "attachmentsByRange": attachments], "WFSerializationType": "WFTextTokenString"]
        }
        func output(_ name: String, _ id: String) -> [String: Any] {
            ["Type": "ActionOutput", "OutputName": name, "OutputUUID": id]
        }
        let actions: [[String: Any]] = [
            ["WFWorkflowActionIdentifier": "is.workflow.actions.urlencode",
             "WFWorkflowActionParameters": [
                "UUID": encodeID,
                "WFEncodeMode": "Encode",
                "WFText": text(object, attachments: ["{0, 1}": ["Type": "ExtensionInput"]]),
             ] as [String: Any]],
            ["WFWorkflowActionIdentifier": "is.workflow.actions.url",
             "WFWorkflowActionParameters": [
                "UUID": linkID,
                "WFURLActionURL": text(prefix + object,
                                       attachments: ["{\(prefix.utf16.count), 1}": output("URL Encoded Text", encodeID)]),
             ] as [String: Any]],
            ["WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
             "WFWorkflowActionParameters": [
                "WFInput": ["Value": output("URL", linkID), "WFSerializationType": "WFTextTokenAttachment"],
             ] as [String: Any]],
        ]
        let root: [String: Any] = [
            "WFWorkflowClientVersion": "2900",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowIcon": ["WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 59511],
            "WFWorkflowImportQuestions": [Any](),
            "WFWorkflowTypes": ["QuickActions"],
            "WFQuickActionSurfaces": ["Services"],
            "WFWorkflowInputContentItemClasses": ["WFStringContentItem"],
            "WFWorkflowNoInputBehavior": ["Name": "WFWorkflowNoInputBehaviorGetClipboard", "Parameters": [String: Any]()],
            "WFWorkflowActions": actions,
        ]
        return ShortcutFile(fileName: "\(action.title) with Uficast.shortcut",
                            data: try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0))
    }
}
