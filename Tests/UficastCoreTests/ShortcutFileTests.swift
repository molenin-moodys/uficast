import Foundation
import Testing
import UficastCore

private func root(_ action: AITextAction) throws -> [String: Any] {
    let data = try #require(ShortcutFile.aiText(action).data)
    return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

private func actions(_ action: AITextAction) throws -> [[String: Any]] {
    try #require(try root(action)["WFWorkflowActions"] as? [[String: Any]])
}

@Test func theFileIsNamedAfterTheActionAndIsABinaryPropertyList() throws {
    let file = ShortcutFile.aiText(.rewrite)
    #expect(file.fileName == "Rewrite with Uficast.shortcut")
    #expect(ShortcutFile.aiText(.translate).fileName == "Translate with Uficast.shortcut")
    let data = try #require(file.data)
    var format = PropertyListSerialization.PropertyListFormat.xml
    _ = try PropertyListSerialization.propertyList(from: data, format: &format)
    #expect(format == .binary)
}

@Test func theShortcutTakesTextFromQuickActionsAndFallsBackToTheClipboard() throws {
    let values = try root(.rewrite)
    #expect(values["WFWorkflowTypes"] as? [String] == ["QuickActions"])
    #expect(values["WFQuickActionSurfaces"] as? [String] == ["Services"])
    #expect(values["WFWorkflowInputContentItemClasses"] as? [String] == ["WFStringContentItem"])
    let behavior = try #require(values["WFWorkflowNoInputBehavior"] as? [String: Any])
    #expect(behavior["Name"] as? String == "WFWorkflowNoInputBehaviorGetClipboard")
    #expect(values["WFWorkflowClientVersion"] is String)
    #expect(values["WFWorkflowMinimumClientVersion"] is Int)
}

@Test func theActionsEncodeTheInputBuildTheLinkAndOpenIt() throws {
    for action in AITextAction.allCases {
        let list = try actions(action)
        #expect(list.compactMap { $0["WFWorkflowActionIdentifier"] as? String } == [
            "is.workflow.actions.urlencode", "is.workflow.actions.url", "is.workflow.actions.openurl",
        ])
        let encode = try #require(list[0]["WFWorkflowActionParameters"] as? [String: Any])
        let link = try #require(list[1]["WFWorkflowActionParameters"] as? [String: Any])
        let open = try #require(list[2]["WFWorkflowActionParameters"] as? [String: Any])

        #expect(encode["WFEncodeMode"] as? String == "Encode")
        let input = try #require(encode["WFText"] as? [String: Any])
        #expect(input["WFSerializationType"] as? String == "WFTextTokenString")
        let inputValue = try #require(input["Value"] as? [String: Any])
        #expect(inputValue["string"] as? String == "\u{FFFC}")
        let inputAttachments = try #require(inputValue["attachmentsByRange"] as? [String: [String: Any]])
        #expect(inputAttachments["{0, 1}"]?["Type"] as? String == "ExtensionInput")

        // The link is the fixed prefix followed by the encoded text; the attachment sits right after the prefix.
        let prefix = AITextURL.prefix(for: action)
        let linkText = try #require(link["WFURLActionURL"] as? [String: Any])
        let linkValue = try #require(linkText["Value"] as? [String: Any])
        #expect(linkValue["string"] as? String == prefix + "\u{FFFC}")
        let linkAttachments = try #require(linkValue["attachmentsByRange"] as? [String: [String: Any]])
        let attachment = try #require(linkAttachments["{\(prefix.utf16.count), 1}"])
        #expect(attachment["Type"] as? String == "ActionOutput")
        #expect(attachment["OutputUUID"] as? String == encode["UUID"] as? String)

        let opened = try #require(open["WFInput"] as? [String: Any])
        #expect(opened["WFSerializationType"] as? String == "WFTextTokenAttachment")
        let openedValue = try #require(opened["Value"] as? [String: Any])
        #expect(openedValue["Type"] as? String == "ActionOutput")
        #expect(openedValue["OutputUUID"] as? String == link["UUID"] as? String)
        #expect((encode["UUID"] as? String) != (link["UUID"] as? String))
    }
}
