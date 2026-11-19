import Foundation

/// Reads directory entries and bounded script headers, never executes them.
public enum ScriptFolderCatalog {
    public struct Refresh: Sendable {
        public var configuration: Configuration
        public var notices: [String]
        public var found: Int
    }

    public static func refresh(_ configuration: Configuration) -> Refresh {
        let files = FileManager.default
        var updated = configuration
        var notices: [String] = []
        var available: Set<String> = []
        var seen: Set<String> = []
        var discovered: [ScriptCommand] = []
        let roots = Array(Set(configuration.scriptDirectories.map { canonical($0) })).sorted()
        updated.scriptDirectories = roots
        for root in roots {
            let directory = URL(fileURLWithPath: root, isDirectory: true)
            let children: [URL]
            do {
                children = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            } catch { notices.append("Could not read script folder: \(directory.lastPathComponent)."); continue }
            available.insert(root)
            for child in children.sorted(by: { $0.path < $1.path }) {
                let url = child.resolvingSymlinksInPath().standardizedFileURL
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let ext = child.pathExtension.lowercased()
                guard ["sh", "bash", "zsh", "py", "applescript", "scpt"].contains(ext) || ext.isEmpty else { continue }
                guard seen.insert(url.path).inserted else { continue }
                do {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let header = String(decoding: try handle.read(upToCount: 32 * 1024) ?? Data(), as: UTF8.self)
                    if ext.isEmpty && !header.hasPrefix("#!") { continue }
                    var command = try command(url: url, header: header, isExecutable: files.isExecutableFile(atPath: url.path))
                    command.sourceDirectory = root
                    discovered.append(command)
                } catch {
                    notices.append("\(child.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        let configured = Set(roots)
        updated.scripts.removeAll { command in
            guard let source = command.sourceDirectory else { return false }
            let root = canonical(source)
            return !configured.contains(root) || (available.contains(root) && !seen.contains(canonical(command.path)))
        }
        // A file keeps its existing ID, alias, enabled state and edited options.
        // Manual commands referring to the same file are never duplicated.
        var existing = Set(updated.scripts.map { canonical($0.path) })
        for command in discovered where existing.insert(command.path).inserted { updated.scripts.append(command) }
        return Refresh(configuration: updated, notices: notices, found: discovered.count)
    }

    public static func command(url: URL, header: String, isExecutable: Bool) throws -> ScriptCommand {
        var metadata: [String: String] = [:]
        for line in header.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#!") { continue }
            let comment: String
            if line.hasPrefix("#") { comment = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("--") { comment = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            else { break }
            if comment.hasPrefix("@raycast."), let space = comment.firstIndex(where: { $0.isWhitespace }) {
                metadata[String(comment[..<space])] = String(comment[space...]).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !metadata.keys.contains(where: { $0.hasPrefix("@raycast.argument") && $0 != "@raycast.argument1" }) else {
            throw ConfigError.invalid("Only one text argument is supported.")
        }
        var requiresArgument = false
        var placeholder = "Argument"
        if let value = metadata["@raycast.argument1"] {
            struct Argument: Decodable { var type: String; var placeholder: String?; var optional: Bool? }
            guard let argument = try? JSONDecoder().decode(Argument.self, from: Data(value.utf8)),
                  argument.type == "text", argument.optional != true else {
                throw ConfigError.invalid("Only one required text argument is supported.")
            }
            requiresArgument = true
            placeholder = argument.placeholder ?? "Argument"
        }
        let interpreter: String?
        let firstLine = header.components(separatedBy: .newlines).first ?? ""
        if firstLine.hasPrefix("#!") {
            let parts = firstLine.dropFirst(2).split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if parts.count == 1, let path = parts.first, path.hasPrefix("/") { interpreter = path }
            else if parts.count == 2, parts[0] == "/usr/bin/env",
                    let path = ["bash": "/bin/bash", "sh": "/bin/sh", "zsh": "/bin/zsh", "python3": "/usr/bin/python3"][parts[1]] { interpreter = path }
            else if isExecutable { interpreter = nil }
            else { throw ConfigError.invalid("Unsupported shebang; make the file executable or configure its interpreter manually.") }
        } else {
            interpreter = ["sh": "/bin/bash", "bash": "/bin/bash", "zsh": "/bin/zsh", "py": "/usr/bin/python3",
                           "applescript": "/usr/bin/osascript", "scpt": "/usr/bin/osascript"][url.pathExtension.lowercased()]
        }
        let title = metadata["@raycast.title"].flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
        return ScriptCommand(id: "file:\(url.path)", name: title, path: url.path, interpreter: interpreter,
                             requiresArgument: requiresArgument, argumentPlaceholder: placeholder)
    }

    private static func canonical(_ path: String) -> String { Configuration.fileURL(path).resolvingSymlinksInPath().path }
}
