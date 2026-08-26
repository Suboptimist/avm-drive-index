import Foundation

/// One file on a source volume, offered for copying.
struct SourceFile: Identifiable, Hashable {
    let id: String        // full path, unique
    let url: URL
    let name: String
    let folder: String    // parent folder relative to the volume root ("" at the top)
    let size: Int64
}

/// Memory cards are deliberately left out of the catalogue — they get
/// reformatted constantly and would bury the real drives. They are still
/// useful while they are plugged in, though, so the app finds them itself and
/// shows them for as long as they are mounted.
enum CardVolumes {

    struct Card {
        let name: String
        let url: URL
        let format: String
        let sizeBytes: Int64
        let freeBytes: Int64
    }

    private static let cardProtocols: Set<String> = [
        "secure digital", "sd", "sd/mmc", "mmc",
    ]

    /// Matches the patterns the scanner uses to spot cards behind a reader.
    private static func looksLikeCard(_ text: String) -> Bool {
        let lowered = text.lowercased()
        for needle in ["sd card", "sdhc", "sdxc", "sd/mmc", "card reader",
                       "multi-card", "multi card", "cfast", "compactflash",
                       "xd-picture", "memory card"] {
            if lowered.contains(needle) { return true }
        }
        return false
    }

    static func diskutilInfo(for url: URL) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return (try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)) as? [String: Any]
    }

    /// Decides whether one mounted volume is a memory card.
    static func card(from info: [String: Any], name: String, url: URL) -> Card? {
        let bus = (info["BusProtocol"] as? String ?? "").lowercased()
        let media = (info["MediaName"] as? String ?? "") + " "
            + (info["DeviceMediaName"] as? String ?? "")
        let removable = (info["RemovableMedia"] as? Bool) ?? false

        let isCard = cardProtocols.contains(bus) || looksLikeCard(media)
        guard isCard, removable || cardProtocols.contains(bus) else { return nil }

        let size = (info["TotalSize"] as? NSNumber)?.int64Value
            ?? (info["Size"] as? NSNumber)?.int64Value ?? 0
        var free = (info["FreeSpace"] as? NSNumber)?.int64Value ?? 0
        if free == 0, let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityKey]),
           let available = values.volumeAvailableCapacity {
            free = Int64(available)
        }
        return Card(name: info["VolumeName"] as? String ?? name,
                    url: url,
                    format: (info["FilesystemType"] as? String ?? "").uppercased(),
                    sizeBytes: size,
                    freeBytes: free)
    }

    /// Every memory card mounted right now.
    static func connected() -> [Card] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/Volumes") else { return [] }
        var cards: [Card] = []
        for entry in entries.sorted() {
            let url = URL(fileURLWithPath: "/Volumes").appendingPathComponent(entry)
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                continue
            }
            guard let info = diskutilInfo(for: url),
                  let card = card(from: info, name: entry, url: url) else { continue }
            cards.append(card)
        }
        return cards
    }

    // MARK: - Wording that matches the scanner

    /// "127.8 GB" — decimal units, one decimal, no pointless ".0".
    static func sizeText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "unknown" }
        let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var i = 0
        while value >= 1000 && i < units.count - 1 { value /= 1000; i += 1 }
        if i == 0 { return "\(Int(value)) bytes" }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(format: "%.0f %@", rounded, units[i])
        }
        return String(format: "%.1f %@", rounded, units[i])
    }

    /// "107 GB (84% free)"
    static func freeText(size: Int64, free: Int64) -> String {
        guard size > 0, free > 0 else { return "unknown" }
        let percent = Int((Double(free) * 100 / Double(size)).rounded())
        return "\(sizeText(free)) (\(percent)% free)"
    }

    static func usedPercent(size: Int64, free: Int64) -> Int? {
        guard size > 0, free >= 0 else { return nil }
        return max(0, min(100, Int((Double(size - free) * 100 / Double(size)).rounded())))
    }

    // MARK: - Reading a volume live

    /// The forms a volume's path can take. The enumerator may hand back
    /// resolved paths (/private/var/...) even when it was given the unresolved
    /// one (/var/...), so relative paths are worked out by prefix rather than
    /// by counting components.
    private static func rootPrefixes(for root: URL) -> [String] {
        var prefixes: [String] = []
        for candidate in [root.standardizedFileURL.path,
                          root.resolvingSymlinksInPath().standardizedFileURL.path] {
            let withSlash = candidate.hasSuffix("/") ? candidate : candidate + "/"
            if !prefixes.contains(withSlash) { prefixes.append(withSlash) }
        }
        return prefixes
    }

    private static func relativePath(of item: URL, prefixes: [String]) -> String? {
        let path = item.standardizedFileURL.path
        for prefix in prefixes where path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return nil
    }

    /// Walks a mounted volume and returns its files. Read fresh rather than
    /// from the index, because a card's contents change constantly and the
    /// index is a capped snapshot.
    static func files(at root: URL, maxDepth: Int = 8, maxFiles: Int = 20_000) -> [SourceFile] {
        let fm = FileManager.default
        let prefixes = rootPrefixes(for: root)
        guard let walker = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [SourceFile] = []
        for case let item as URL in walker {
            if found.count >= maxFiles { break }
            guard let relative = relativePath(of: item, prefixes: prefixes), !relative.isEmpty
            else { continue }

            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let depth = relative.split(separator: "/").count
            if values?.isDirectory == true {
                if depth >= maxDepth { walker.skipDescendants() }
                continue
            }
            if item.lastPathComponent.hasPrefix(".") { continue }

            let folder: String
            if let slash = relative.lastIndex(of: "/") {
                folder = String(relative[relative.startIndex..<slash])
            } else {
                folder = ""
            }
            found.append(SourceFile(
                id: item.path,
                url: item,
                name: item.lastPathComponent,
                folder: folder,
                size: Int64(values?.fileSize ?? 0)))
        }
        return found.sorted {
            $0.folder == $1.folder
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.folder.localizedStandardCompare($1.folder) == .orderedAscending
        }
    }

    /// Groups a flat file list into the tree the Contents view draws.
    static func tree(from files: [SourceFile], rootPath: String) -> [FolderNode] {
        var byFolder: [String: [SourceFile]] = [:]
        for file in files { byFolder[file.folder, default: []].append(file) }

        func node(for folder: String) -> [FolderNode] {
            var children: [FolderNode] = []
            let prefix = folder.isEmpty ? "" : folder + "/"
            let subfolders = Set(byFolder.keys.compactMap { key -> String? in
                guard key.hasPrefix(prefix), key != folder else { return nil }
                let rest = String(key.dropFirst(prefix.count))
                return rest.isEmpty ? nil : String(rest.split(separator: "/")[0])
            })
            for name in subfolders.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                let path = prefix + name
                let kids = node(for: path)
                children.append(FolderNode(id: rootPath + "/" + path, name: name, relPath: path,
                                           isFile: false, sizeLabel: nil,
                                           children: kids.isEmpty ? nil : kids))
            }
            for file in (byFolder[folder] ?? []) {
                children.append(FolderNode(
                    id: file.id, name: file.name,
                    relPath: file.folder.isEmpty ? file.name : file.folder + "/" + file.name,
                    isFile: true,
                    sizeLabel: InfoFileParser.byteFmt.string(fromByteCount: file.size),
                    children: nil))
            }
            return children
        }
        return node(for: "")
    }
}
