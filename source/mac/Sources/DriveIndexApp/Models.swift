import Foundation

struct HistoryEntry: Identifiable, Hashable {
    let id: Int
    let date: Date?
    let dateString: String
    let user: String
}

struct FolderNode: Identifiable, Hashable {
    let id: String            // full path inside the index, unique
    let name: String
    let relPath: String       // path on the drive, e.g. "DCIM/100MSDCF"
    let isFile: Bool
    let sizeLabel: String?    // formatted size, files only
    let children: [FolderNode]?   // nil = leaf (no disclosure arrow)
}

struct DriveRecord: Identifiable, Hashable {
    let id: String            // index folder path
    let indexFolderName: String   // e.g. "Untitled (2)"
    let name: String              // the drive's real volume name
    let size: String
    let freeSpace: String   // snapshot from the last connection
    let usedPercent: Int?   // 0-100, for the usage bar; nil when unknown
    let format: String
    let uuid: String?
    let lastConnected: Date?
    let lastConnectedString: String
    let lastUser: String
    let foldersNote: String
    let history: [HistoryEntry]
    let folderURL: URL            // the drive's folder inside the index
    let volumeURL: URL?           // where the drive is mounted right now, if it is
    let isCard: Bool              // a memory card: shown while mounted, never catalogued
    let isRemovableMedia: Bool    // a card, stick, recorder — something you offload from
    let folderTree: [FolderNode]

    var isConnected: Bool { volumeURL != nil }

    // Full value equality (synthesized) — SwiftUI relies on it to know when
    // a row's content changed, e.g. connected → disconnected.
}

enum InfoFileParser {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Parses one "_DRIVE INFO.txt" written by drive_indexer.sh.
    /// `mountedVolume` maps (uuid, name) to the live mount point, if any.
    static func parse(infoFile: URL, folderURL: URL,
                      mountedVolume: (String?, String) -> URL?,
                      isRemovable: (URL) -> Bool = { _ in false }) -> DriveRecord? {
        guard let text = try? String(contentsOf: infoFile, encoding: .utf8) else { return nil }

        func field(_ label: String) -> String {
            for line in text.split(separator: "\n") where line.hasPrefix(label) {
                return line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
            }
            return ""
        }

        let name = field("DRIVE:")
        guard !name.isEmpty else { return nil }
        let uuidRaw = field("UUID:")
        let uuid = (uuidRaw.isEmpty || uuidRaw == "none") ? nil : uuidRaw
        let contentsNote = [field("FOLDERS:"), field("FILES:")]
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")

        var history: [HistoryEntry] = []
        var inHistory = false
        for line in text.split(separator: "\n") {
            if line.hasPrefix("CONNECTION HISTORY") { inHistory = true; continue }
            guard inHistory else { continue }
            let parts = line.components(separatedBy: " — ")
            guard parts.count >= 2 else { continue }
            let dateString = parts[0].trimmingCharacters(in: .whitespaces)
            history.append(HistoryEntry(
                id: history.count,
                date: dateFormatter.date(from: dateString),
                dateString: dateString,
                user: parts.dropFirst().joined(separator: " — ").trimmingCharacters(in: .whitespaces)
            ))
        }

        let lastConnectedString = field("LAST CONNECTED:")
        let volume = mountedVolume(uuid, name)
        return DriveRecord(
            id: folderURL.path,
            indexFolderName: folderURL.lastPathComponent,
            name: name,
            size: field("SIZE:"),
            freeSpace: field("FREE SPACE:"),
            usedPercent: Int(field("USED PERCENT:")),
            format: field("FORMAT:"),
            uuid: uuid,
            lastConnected: dateFormatter.date(from: lastConnectedString),
            lastConnectedString: lastConnectedString,
            lastUser: field("LAST USED BY:"),
            foldersNote: contentsNote,
            history: history,
            folderURL: folderURL,
            volumeURL: volume,
            isCard: false,
            isRemovableMedia: volume.map(isRemovable) ?? false,
            folderTree: contentTree(at: folderURL)
        )
    }

    // MARK: Content tree (mirrored folders + "_FILE LIST.txt")

    static let byteFmt: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    /// Builds the browse tree: folders come from the mirrored folder
    /// structure next to the info file, files from "_FILE LIST.txt"
    /// (one "size_in_bytes|relative/path" per line).
    static func contentTree(at url: URL) -> [FolderNode] {
        let root = TreeNode()
        addMirroredFolders(at: url, into: root)

        let listFile = url.appendingPathComponent("_FILE LIST.txt")
        if let text = try? String(contentsOf: listFile, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                guard let bar = line.firstIndex(of: "|") else { continue }
                let size = Int64(line[line.startIndex..<bar]) ?? 0
                let rel = String(line[line.index(after: bar)...])
                var comps = rel.split(separator: "/").map(String.init)
                guard let fileName = comps.popLast(), !fileName.isEmpty else { continue }
                root.insertFile(dirs: comps, name: fileName, size: size)
            }
        }
        return root.build(idPrefix: url.path, relPrefix: "")
    }

    private static func addMirroredFolders(at url: URL, into node: TreeNode) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return }
        for item in items
        where (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            addMirroredFolders(at: item, into: node.child(item.lastPathComponent))
        }
    }

    private final class TreeNode {
        var dirs: [String: TreeNode] = [:]
        var files: [String: Int64] = [:]

        func child(_ name: String) -> TreeNode {
            if let existing = dirs[name] { return existing }
            let created = TreeNode()
            dirs[name] = created
            return created
        }

        func insertFile(dirs path: [String], name: String, size: Int64) {
            var node = self
            for dir in path { node = node.child(dir) }
            node.files[name] = size
        }

        /// Folders first, then files, each alphabetical.
        func build(idPrefix: String, relPrefix: String) -> [FolderNode] {
            var out: [FolderNode] = []
            for (name, sub) in dirs.sorted(by: {
                $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }) {
                let rel = relPrefix.isEmpty ? name : "\(relPrefix)/\(name)"
                let kids = sub.build(idPrefix: idPrefix, relPrefix: rel)
                out.append(FolderNode(id: "\(idPrefix)/\(rel)", name: name, relPath: rel,
                                      isFile: false, sizeLabel: nil,
                                      children: kids.isEmpty ? nil : kids))
            }
            for (name, size) in files.sorted(by: {
                $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }) {
                let rel = relPrefix.isEmpty ? name : "\(relPrefix)/\(name)"
                out.append(FolderNode(id: "\(idPrefix)/\(rel)", name: name, relPath: rel,
                                      isFile: true,
                                      sizeLabel: InfoFileParser.byteFmt.string(fromByteCount: size),
                                      children: nil))
            }
            return out
        }
    }
}
