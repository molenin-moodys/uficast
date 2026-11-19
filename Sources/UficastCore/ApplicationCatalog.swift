import Foundation

public enum ApplicationCatalog {
    public struct Snapshot: Sendable {
        public var entries: [LauncherEntry]
        public var unavailableRoots: [URL]
    }

    public static var defaultRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
    }

    /// Runs off the UI actor. Root order determines which duplicate bundle wins.
    public static func discover(roots: [URL]) -> Snapshot {
        let files = FileManager.default
        var records: [String: LauncherEntry] = [:]
        var unavailable: [URL] = []
        for root in roots {
            var isDirectory: ObjCBool = false
            guard files.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                unavailable.append(root)
                continue
            }
            let candidates: [URL]
            if root.pathExtension.lowercased() == "app" { candidates = [root] }
            else {
                guard let enumerator = files.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                    unavailable.append(root)
                    continue
                }
                var found: [URL] = []
                for case let url as URL in enumerator {
                    if url.pathExtension.lowercased() == "app" {
                        enumerator.skipDescendants()
                        found.append(url)
                    }
                }
                candidates = found.sorted { $0.path < $1.path }
            }
            for candidate in candidates {
                let url = candidate.resolvingSymlinksInPath().standardizedFileURL
                guard let bundle = Bundle(url: url), let info = bundle.infoDictionary,
                      (info["CFBundlePackageType"] as? String ?? "APPL") == "APPL" else { continue }
                let identifier = bundle.bundleIdentifier
                let id = identifier.map { "app:\($0)" } ?? "app-path:\(url.path)"
                guard records[id] == nil else { continue }
                let localized = bundle.localizedInfoDictionary ?? [:]
                let name = localized["CFBundleDisplayName"] as? String ?? info["CFBundleDisplayName"] as? String
                    ?? localized["CFBundleName"] as? String ?? info["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                records[id] = LauncherEntry(id: id, name: name, fileURL: url)
            }
        }
        return Snapshot(entries: records.values.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }, unavailableRoots: unavailable)
    }
}
