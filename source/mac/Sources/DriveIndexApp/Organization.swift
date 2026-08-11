import Foundation

/// User-defined ordering and grouping of drives in the sidebar.
/// Saved as ".drive-organization.json" inside the Drive Index folder,
/// so it travels with the index itself.
struct DriveGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var driveNames: [String]     // index folder names, in display order
}

struct Organization: Codable, Equatable {
    var ungrouped: [String] = [] // drives not in any folder, in display order
    var groups: [DriveGroup] = []
}

extension IndexStore {
    private var orgFile: URL? {
        indexFolder?.appendingPathComponent(".drive-organization.json")
    }

    func record(named name: String) -> DriveRecord? {
        drives.first { $0.indexFolderName == name }
    }

    func loadOrg() {
        guard let file = orgFile,
              let data = try? Data(contentsOf: file),
              let loaded = try? JSONDecoder().decode(Organization.self, from: data)
        else { org = Organization(); return }
        org = loaded
    }

    func saveOrg() {
        guard let file = orgFile else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(org) {
            try? data.write(to: file)
        }
    }

    /// Keeps the organization in sync with what's actually indexed:
    /// drops removed drives, files new ones at the top of the main list.
    func reconcileOrg() {
        var o = org
        let known = Set(drives.map(\.indexFolderName))
        o.ungrouped.removeAll { !known.contains($0) }
        for i in o.groups.indices {
            o.groups[i].driveNames.removeAll { !known.contains($0) }
        }
        let placed = Set(o.ungrouped + o.groups.flatMap(\.driveNames))
        // `drives` is sorted newest-first, so insert new arrivals at the top
        // in that same order.
        for drive in drives.reversed() where !placed.contains(drive.indexFolderName) {
            o.ungrouped.insert(drive.indexFolderName, at: 0)
        }
        if o != org {
            org = o
            saveOrg()
        }
    }

    // MARK: Reordering

    func moveUngrouped(from source: IndexSet, to destination: Int) {
        org.ungrouped.move(fromOffsets: source, toOffset: destination)
        saveOrg()
    }

    func moveInGroup(_ groupID: UUID, from source: IndexSet, to destination: Int) {
        guard let i = org.groups.firstIndex(where: { $0.id == groupID }) else { return }
        org.groups[i].driveNames.move(fromOffsets: source, toOffset: destination)
        saveOrg()
    }

    // MARK: Folders

    @discardableResult
    func addGroup(named name: String) -> UUID {
        let group = DriveGroup(id: UUID(), name: name, driveNames: [])
        org.groups.append(group)
        saveOrg()
        return group.id
    }

    func renameGroup(_ groupID: UUID, to name: String) {
        guard let i = org.groups.firstIndex(where: { $0.id == groupID }) else { return }
        org.groups[i].name = name
        saveOrg()
    }

    /// Deletes the folder itself; its drives go back to the main list.
    func deleteGroup(_ groupID: UUID) {
        guard let i = org.groups.firstIndex(where: { $0.id == groupID }) else { return }
        org.ungrouped.append(contentsOf: org.groups[i].driveNames)
        org.groups.remove(at: i)
        saveOrg()
    }

    func moveGroup(_ groupID: UUID, by delta: Int) {
        guard let i = org.groups.firstIndex(where: { $0.id == groupID }) else { return }
        let j = i + delta
        guard org.groups.indices.contains(j) else { return }
        org.groups.swapAt(i, j)
        saveOrg()
    }

    /// Moves a drive into a folder (or out of all folders if nil).
    func move(_ drive: DriveRecord, toGroup groupID: UUID?) {
        let name = drive.indexFolderName
        org.ungrouped.removeAll { $0 == name }
        for i in org.groups.indices {
            org.groups[i].driveNames.removeAll { $0 == name }
        }
        if let groupID, let i = org.groups.firstIndex(where: { $0.id == groupID }) {
            org.groups[i].driveNames.append(name)
        } else {
            org.ungrouped.append(name)
        }
        saveOrg()
    }
}
