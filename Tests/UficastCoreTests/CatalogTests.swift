import Foundation
import Testing
import UficastCore

@Test func catalogDeduplicatesBundlesAndSkipsNestedHelpers() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: root) }
    func app(_ path: String, _ id: String, _ name: String) throws {
        let contents = root.appendingPathComponent(path).appendingPathComponent("Contents")
        try files.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": id, "CFBundleName": name, "CFBundlePackageType": "APPL",
        ], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
    }
    try app("A.app", "fixture.a", "Alpha")
    try app("A.app/Contents/Helpers/Hidden.app", "fixture.hidden", "Hidden")
    try app("Utilities/B.app", "fixture.b", "Beta")
    try app("Z.app", "fixture.a", "Duplicate")
    let missing = root.appendingPathComponent("missing")
    let snapshot = ApplicationCatalog.discover(roots: [root, missing])
    #expect(snapshot.entries.map(\.name) == ["Alpha", "Beta"])
    #expect(snapshot.entries.map(\.id) == ["app:fixture.a", "app:fixture.b"])
    #expect(snapshot.unavailableRoots == [missing])
    #expect(ApplicationCatalog.discover(roots: [root.appendingPathComponent("A.app")]).entries.count == 1)
}
