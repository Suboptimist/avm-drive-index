import Foundation

/// A folder or file in the copy picker.
struct CopyNode: Identifiable, Hashable {
    let id: String            // full path, unique
    let name: String
    let isFile: Bool
    let size: Int64
    let url: URL?             // files only
    let children: [CopyNode]?
}

/// One file to copy, and where it should land relative to the chosen folder.
struct CopyItem: Identifiable, Hashable {
    var id: String { source.path }
    let source: URL
    let relativePath: String
    let size: Int64
    var name: String { (relativePath as NSString).lastPathComponent }
}

enum CopyPlan {

    /// Builds the browsable tree from a flat file list.
    static func tree(from files: [SourceFile], rootPath: String) -> [CopyNode] {
        var byFolder: [String: [SourceFile]] = [:]
        for file in files { byFolder[file.folder, default: []].append(file) }
        var folders = Set(byFolder.keys)
        // Make sure every intermediate folder exists, even if it holds no files
        // directly.
        for folder in byFolder.keys where !folder.isEmpty {
            var parts = folder.split(separator: "/").map(String.init)
            while parts.count > 1 {
                parts.removeLast()
                folders.insert(parts.joined(separator: "/"))
            }
        }

        func build(_ folder: String) -> [CopyNode] {
            let prefix = folder.isEmpty ? "" : folder + "/"
            var nodes: [CopyNode] = []
            let childFolders = folders.compactMap { candidate -> String? in
                guard candidate != folder, candidate.hasPrefix(prefix) else { return nil }
                let rest = String(candidate.dropFirst(prefix.count))
                guard !rest.isEmpty else { return nil }
                return String(rest.split(separator: "/")[0])
            }
            for name in Set(childFolders).sorted(by: {
                $0.localizedStandardCompare($1) == .orderedAscending
            }) {
                let path = prefix + name
                nodes.append(CopyNode(id: rootPath + "/" + path, name: name, isFile: false,
                                      size: 0, url: nil, children: build(path)))
            }
            for file in (byFolder[folder] ?? []).sorted(by: {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }) {
                nodes.append(CopyNode(id: file.id, name: file.name, isFile: true,
                                      size: file.size, url: file.url, children: nil))
            }
            return nodes
        }
        return build("")
    }

    /// Every file underneath a node, itself included when it is a file.
    static func files(under node: CopyNode) -> [CopyNode] {
        if node.isFile { return [node] }
        return (node.children ?? []).flatMap { files(under: $0) }
    }

    enum TickState { case none, some, all }

    static func state(of node: CopyNode, selected: Set<String>) -> TickState {
        let all = files(under: node)
        guard !all.isEmpty else { return .none }
        let chosen = all.filter { selected.contains($0.id) }.count
        if chosen == 0 { return .none }
        return chosen == all.count ? .all : .some
    }

    /// Ticking a folder takes everything in it; unticking clears it.
    static func toggle(_ node: CopyNode, in selected: inout Set<String>) {
        let all = files(under: node).map(\.id)
        if state(of: node, selected: selected) == .all {
            selected.subtract(all)
        } else {
            selected.formUnion(all)
        }
    }

    /// Works out what lands where.
    ///
    /// A file ticked on its own goes straight into the chosen folder. Tick a
    /// whole folder and that folder is recreated at the destination with its
    /// contents inside, so a card's structure survives when you want it to.
    static func items(in nodes: [CopyNode], selected: Set<String>) -> [CopyItem] {
        var out: [CopyItem] = []

        func walk(_ node: CopyNode, prefix: String?) {
            if node.isFile {
                guard selected.contains(node.id), let url = node.url else { return }
                let relative = prefix.map { $0 + "/" + node.name } ?? node.name
                out.append(CopyItem(source: url, relativePath: relative, size: node.size))
                return
            }
            let children = node.children ?? []
            if prefix == nil, state(of: node, selected: selected) == .all {
                for child in children { walk(child, prefix: node.name) }   // keep the folder
            } else if let prefix {
                for child in children { walk(child, prefix: prefix + "/" + node.name) }
            } else {
                for child in children { walk(child, prefix: nil) }
            }
        }

        for node in nodes { walk(node, prefix: nil) }
        return out
    }

    static func totalBytes(of items: [CopyItem]) -> Int64 {
        items.reduce(0) { $0 + $1.size }
    }
}
