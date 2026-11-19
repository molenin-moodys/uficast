import Foundation
import Testing
import UficastCore

private func folderFixture() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Test func importsRaycastHeaderAsDataWithoutRunningScript() throws {
    let directory = try folderFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let marker = directory.appendingPathComponent("must-not-exist")
    let source = directory.appendingPathComponent("search.sh")
    try """
    #!/usr/bin/env bash
    # @raycast.title Search Example
    # @raycast.argument1 {"type":"text","placeholder":"Search text"}
    touch "\(marker.path)"
    # @raycast.title This is body data
    """.write(to: source, atomically: true, encoding: .utf8)
    var config = Configuration()
    config.scriptDirectories = [directory.path]
    let result = ScriptFolderCatalog.refresh(config)
    let script = try #require(result.configuration.scripts.first)
    #expect(result.found == 1 && result.notices.isEmpty)
    #expect(script.name == "Search Example")
    #expect(script.interpreter == "/bin/bash")
    #expect(script.requiresArgument && script.argumentPlaceholder == "Search text")
    #expect(script.sourceDirectory == directory.path)
    #expect(script.resultMode == .discard)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    #expect(try Configuration.decode(result.configuration.encoded()) == result.configuration)
}

@Test func folderRefreshKeepsUserOptionsDeduplicatesAndPrunesOnlyAvailableManagedFiles() throws {
    let directory = try folderFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("first.sh")
    try "#!/bin/zsh\necho fixture".write(to: source, atomically: true, encoding: .utf8)
    var config = Configuration()
    config.scriptDirectories = [directory.path, directory.path]
    config = ScriptFolderCatalog.refresh(config).configuration
    #expect(config.scripts[0].interpreter == "/bin/zsh")
    config.scripts[0].name = "Custom Name"
    config.scripts[0].alias = "custom"
    config.scripts[0].isEnabled = false
    let original = config.scripts[0]
    config = ScriptFolderCatalog.refresh(config).configuration
    #expect(config.scriptDirectories == [directory.path])
    #expect(config.scripts == [original])
    let missing = directory.appendingPathComponent("offline", isDirectory: true).path
    config.scriptDirectories.append(missing)
    let offline = ScriptCommand(name: "Offline", path: missing + "/a.sh", sourceDirectory: missing)
    config.scripts.append(offline)
    let manual = ScriptCommand(name: "Manual", path: "/fixture/manual.sh")
    config.scripts.append(manual)
    try FileManager.default.removeItem(at: source)
    let refreshed = ScriptFolderCatalog.refresh(config)
    #expect(refreshed.configuration.scripts == [offline, manual])
    #expect(!refreshed.notices.isEmpty)
    var disconnected = refreshed.configuration
    disconnected.scriptDirectories = []
    #expect(ScriptFolderCatalog.refresh(disconnected).configuration.scripts == [manual])
}

@Test func scriptFoldersSkipHiddenNestedAndUnsupportedArgumentFilesAndKeepManualDuplicates() throws {
    let directory = try folderFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    try "echo hidden".write(to: directory.appendingPathComponent(".hidden.sh"), atomically: true, encoding: .utf8)
    try "notes".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try "not a script".write(to: directory.appendingPathComponent("LICENSE"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("nested.sh"), withIntermediateDirectories: true)
    try "# @raycast.argument2 {}\necho no".write(to: directory.appendingPathComponent("unsupported.sh"), atomically: true, encoding: .utf8)
    let source = directory.appendingPathComponent("manual.py")
    try "print('fixture')".write(to: source, atomically: true, encoding: .utf8)
    let manual = ScriptCommand(name: "Existing", alias: "existing", path: source.path, interpreter: "/usr/bin/python3")
    var config = Configuration()
    config.scripts = [manual]
    config.scriptDirectories = [directory.path]
    let result = ScriptFolderCatalog.refresh(config)
    #expect(result.found == 1)
    #expect(result.notices.count == 1)
    #expect(result.configuration.scripts == [manual])
}

@Test func shebangAndArgumentValidationAvoidGuessingUnsupportedInvocation() throws {
    let url = URL(fileURLWithPath: "/fixture/example.sh")
    #expect(throws: ConfigError.self) { try ScriptFolderCatalog.command(url: url, header: "#!/usr/bin/env -S python3 -u", isExecutable: false) }
    #expect(try ScriptFolderCatalog.command(url: url, header: "#!/usr/bin/env -S python3 -u", isExecutable: true).interpreter == nil)
    #expect(throws: ConfigError.self) { try ScriptFolderCatalog.command(url: url, header: "# @raycast.argument1 {\"type\":\"text\",\"optional\":true}", isExecutable: false) }
    #expect(throws: ConfigError.self) { try ScriptFolderCatalog.command(url: url, header: "# @raycast.argument1 invalid-json", isExecutable: false) }
    #expect(try ScriptFolderCatalog.command(url: URL(fileURLWithPath: "/fixture/example.scpt"), header: "", isExecutable: false).interpreter == "/usr/bin/osascript")
}

@Test func legacyConfigurationDefaultsToNoScriptFolders() throws {
    let legacy = Data("{\"schemaVersion\":1,\"applicationRoots\":[],\"applications\":{},\"scripts\":[]}".utf8)
    #expect(try Configuration.decode(legacy).scriptDirectories.isEmpty)
    var config = Configuration()
    config.scriptDirectories = ["relative"]
    #expect(throws: ConfigError.self) { try config.validated() }
}
