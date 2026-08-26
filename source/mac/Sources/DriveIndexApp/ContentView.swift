import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: IndexStore
    @State private var selection: String?
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    // Folder management prompts
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var moveAfterCreate: DriveRecord?
    @State private var renameTarget: DriveGroup?
    @State private var renameName = ""
    @State private var copyTarget: DriveRecord?

    var body: some View {
        ZStack {
            Pip.bg.ignoresSafeArea()
            if store.indexFolder == nil {
                MissingIndexView()
            } else {
                mainView
            }
            CRTOverlay().ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .tint(Pip.green)
        .frame(minWidth: 820, minHeight: 480)
    }

    // MARK: - Layout

    private var mainView: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Pip.faint).frame(height: 1)
            HStack(spacing: 0) {
                sidebar.frame(width: 280)
                Rectangle().fill(Pip.faint).frame(width: 1)
                detail
            }
            if !store.watcherInstalled {
                watcherBanner
            }
        }
        .onAppear {
            if selection == nil { selection = store.drives.first?.id }
        }
        .sheet(item: $copyTarget) { record in
            CopyFilesSheet(volumeName: record.indexFolderName,
                           files: store.sourceFiles(for: record),
                           suggestedDestination: destinationSuggestion(excluding: record))
                .environmentObject(store)
        }
        .modifier(DialogsModifier(
            selection: $selection,
            showNewFolder: $showNewFolder,
            newFolderName: $newFolderName,
            moveAfterCreate: $moveAfterCreate,
            renameTarget: $renameTarget,
            renameName: $renameName
        ))
    }

    private var headerBar: some View {
        HStack(spacing: 14) {
            Text("AVM DRIVE INDEX")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Pip.green)
            Spacer()
            searchField
            Button {
                newFolderName = ""
                moveAfterCreate = nil
                showNewFolder = true
            } label: {
                Text("+ Folder")
            }
            .buttonStyle(PipButtonStyle())
            Button {
                store.rescan()
            } label: {
                Text(store.isRescanning ? "Scanning…" : "Rescan")
            }
            .buttonStyle(PipButtonStyle())
            .disabled(store.isRescanning)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Pip.bgRaised)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5))
                .foregroundStyle(Pip.dim)
            TextField("Search index…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Pip.text)
                .focused($searchFocused)
                .frame(width: 190)
                .onExitCommand {
                    searchText = ""
                    searchFocused = false
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Pip.dim)
                }
                .buttonStyle(.plain)
            }
            // Hidden ⌘F target
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Pip.bg))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(searchFocused ? Pip.green.opacity(0.45) : Pip.faint, lineWidth: 1)
        )
    }

    private var detail: some View {
        Group {
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                SearchResultsView(query: searchText, hits: searchHits) { hit in
                    selection = hit.driveID
                    searchText = ""
                }
            } else if let sel = selection, let drive = store.record(withID: sel) {
                DriveDetailView(drive: drive)
            } else {
                PipEmpty(
                    title: "No drive selected",
                    message: "Every external drive ever connected to this Mac is listed on the left — even ones that aren't plugged in right now."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Somewhere sensible to start the destination picker: another drive that
    /// is plugged in, rather than the volume being copied from.
    private func destinationSuggestion(excluding record: DriveRecord) -> URL? {
        store.drives.first { $0.id != record.id && $0.volumeURL != nil }?.volumeURL
    }

    // MARK: - Search

    private var searchHits: [SearchHit] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        var hits: [SearchHit] = []
        outer: for drive in store.drives + store.cards {
            if drive.indexFolderName.lowercased().contains(query) {
                hits.append(SearchHit(
                    id: "drive:\(drive.id)", driveID: drive.id,
                    driveName: drive.indexFolderName, name: drive.indexFolderName,
                    path: "", isFile: false, isDrive: true, sizeLabel: nil
                ))
            }
            var stack = drive.folderTree
            while let node = stack.popLast() {
                if let kids = node.children { stack.append(contentsOf: kids) }
                if node.name.lowercased().contains(query) {
                    hits.append(SearchHit(
                        id: node.id, driveID: drive.id,
                        driveName: drive.indexFolderName, name: node.name,
                        path: node.relPath, isFile: node.isFile,
                        isDrive: false, sizeLabel: node.sizeLabel
                    ))
                    if hits.count >= 400 { break outer }
                }
            }
        }
        return hits
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            Section {
                driveRows(store.org.ungrouped)
                    .onMove { store.moveUngrouped(from: $0, to: $1) }
                if store.org.ungrouped.isEmpty && store.org.groups.isEmpty {
                    Text("No drives indexed yet.\nConnect one and it will appear here.")
                        .font(.system(size: 11))
                        .foregroundStyle(Pip.dim)
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 6)
                }
            } header: {
                sectionHeader("Drives")
            }

            if !store.cards.isEmpty {
                Section {
                    ForEach(store.cards) { card in
                        PipDriveRow(drive: card, selected: selection == card.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = card.id }
                            .contextMenu {
                                Button {
                                    copyTarget = card
                                } label: {
                                    Label("Copy Files…", systemImage: "doc.on.doc")
                                }
                                Button {
                                    store.eject(card)
                                } label: {
                                    Label("Eject", systemImage: "eject.fill")
                                }
                                .disabled(store.ejectingID != nil)
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                } header: {
                    sectionHeader("Cards")
                }
            }

            ForEach(store.org.groups) { group in
                Section {
                    driveRows(group.driveNames)
                        .onMove { store.moveInGroup(group.id, from: $0, to: $1) }
                    if group.driveNames.isEmpty {
                        Text("(empty)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Pip.dim)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    groupHeader(group)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Pip.bg)
        .environment(\.defaultMinListRowHeight, 10)
    }

    private func driveRows(_ names: [String]) -> some DynamicViewContent {
        ForEach(names, id: \.self) { name in
            if let drive = store.record(named: name) {
                PipDriveRow(drive: drive, selected: selection == drive.id)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = drive.id }
                    .contextMenu { rowMenu(drive) }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ drive: DriveRecord) -> some View {
        if drive.isConnected {
            Button {
                copyTarget = drive
            } label: {
                Label("Copy Files…", systemImage: "doc.on.doc")
            }
            Button {
                store.eject(drive)
            } label: {
                Label("Eject", systemImage: "eject.fill")
            }
            .disabled(store.ejectingID != nil)
            Divider()
        }
        Menu("Move to Folder") {
            Button("(No Folder)") { store.move(drive, toGroup: nil) }
            if !store.org.groups.isEmpty { Divider() }
            ForEach(store.org.groups) { group in
                Button(group.name) { store.move(drive, toGroup: group.id) }
            }
            Divider()
            Button("New Folder…") {
                newFolderName = ""
                moveAfterCreate = drive
                showNewFolder = true
            }
        }
        Divider()
        Button(role: .destructive) {
            store.pendingDelete = drive
        } label: {
            Label("Remove from Index…", systemImage: "trash")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Pip.dim)
            Rectangle().fill(Pip.faint).frame(height: 1)
        }
        .padding(.top, 4)
    }

    private func groupHeader(_ group: DriveGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 9))
                .foregroundStyle(Pip.dim)
            Text(group.name)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Pip.dim)
            Rectangle().fill(Pip.faint).frame(height: 1)
        }
        .padding(.top, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename Folder…") {
                renameName = group.name
                renameTarget = group
            }
            Button("Move Folder Up") { store.moveGroup(group.id, by: -1) }
            Button("Move Folder Down") { store.moveGroup(group.id, by: 1) }
            Divider()
            Button(role: .destructive) {
                store.deleteGroup(group.id)
            } label: {
                Text("Delete Folder (Keep Drives)")
            }
        }
    }

    // MARK: - Banner

    private var watcherBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text("Automatic indexing is turned off")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Pip.text)
                Text("Drives connected while this app is closed won't be recorded.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Pip.dim)
            }
            Spacer()
            Button("Turn On") { store.installWatcher() }
                .buttonStyle(PipButtonStyle())
        }
        .padding(10)
        .background(Pip.bgRaised)
        .overlay(Rectangle().fill(Pip.faint).frame(height: 1), alignment: .top)
    }
}

// MARK: - Alerts / prompts (kept in one place)

private struct DialogsModifier: ViewModifier {
    @EnvironmentObject var store: IndexStore
    @Binding var selection: String?
    @Binding var showNewFolder: Bool
    @Binding var newFolderName: String
    @Binding var moveAfterCreate: DriveRecord?
    @Binding var renameTarget: DriveGroup?
    @Binding var renameName: String

    func body(content: Content) -> some View {
        content
            .alert("New Folder", isPresented: $showNewFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Create") {
                    let name = newFolderName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let id = store.addGroup(named: name)
                    if let drive = moveAfterCreate {
                        store.move(drive, toGroup: id)
                    }
                    moveAfterCreate = nil
                }
                Button("Cancel", role: .cancel) { moveAfterCreate = nil }
            } message: {
                Text(moveAfterCreate == nil
                    ? "Folders help you group drives in the sidebar — they don't change anything on the drives themselves."
                    : "The drive will be moved into the new folder.")
            }
            .alert("Rename Folder", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Folder name", text: $renameName)
                Button("Rename") {
                    let name = renameName.trimmingCharacters(in: .whitespaces)
                    if let group = renameTarget, !name.isEmpty {
                        store.renameGroup(group.id, to: name)
                    }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .alert(
                "Remove drive from index?",
                isPresented: Binding(
                    get: { store.pendingDelete != nil },
                    set: { if !$0 { store.pendingDelete = nil } }
                ),
                presenting: store.pendingDelete
            ) { drive in
                Button("Remove \"\(drive.indexFolderName)\"", role: .destructive) {
                    if selection == drive.id { selection = nil }
                    store.deleteIndex(drive)
                }
                Button("Cancel", role: .cancel) {}
            } message: { drive in
                Text(drive.isConnected
                    ? "Its folder list and connection history will be moved to the Trash. Note: this drive is still connected, so it will be indexed again right away — eject it first if you want it off the list."
                    : "Its folder list and connection history will be moved to the Trash. If the drive is ever connected again, a fresh record will be started.")
            }
            .alert(
                "Couldn't Eject",
                isPresented: Binding(
                    get: { store.ejectError != nil },
                    set: { if !$0 { store.ejectError = nil } }
                ),
                presenting: store.ejectError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text("\(error)\n\nA file on the drive is probably still open in some app. Close it and try again.")
            }
    }
}

// MARK: - Search results

struct SearchHit: Identifiable {
    let id: String
    let driveID: String
    let driveName: String
    let name: String
    let path: String
    let isFile: Bool
    let isDrive: Bool
    let sizeLabel: String?
}

struct SearchResultsView: View {
    let query: String
    let hits: [SearchHit]
    let onSelect: (SearchHit) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Pip.dim)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Rectangle().fill(Pip.faint).frame(height: 1)

            if hits.isEmpty {
                PipEmpty(
                    title: "No matches",
                    message: "Nothing in the index matches \"\(query)\". Search covers drive names, folders, and files on every drive ever indexed."
                )
            } else {
                List(hits) { hit in
                    HStack(spacing: 9) {
                        Image(systemName: hit.isDrive
                            ? "externaldrive.fill"
                            : (hit.isFile ? "doc" : "folder.fill"))
                            .font(.system(size: 12))
                            .foregroundStyle(hit.isDrive ? Pip.green : Pip.dim)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hit.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Pip.text)
                                .lineLimit(1)
                            if !hit.path.isEmpty {
                                Text(hit.path.replacingOccurrences(of: "/", with: " ▸ "))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Pip.dim)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if let size = hit.sizeLabel {
                            Text(size)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Pip.dim.opacity(0.75))
                        }
                        Text(hit.driveName)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Pip.green.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Pip.green.opacity(0.10))
                            )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(hit) }
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var summary: String {
        let count = hits.count >= 400 ? "400+" : "\(hits.count)"
        return "\(count) result\(hits.count == 1 ? "" : "s") — click one to open its drive"
    }
}

// MARK: - Sidebar row

struct PipDriveRow: View {
    let drive: DriveRecord
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 14))
                .foregroundStyle(drive.isConnected ? Pip.green : Pip.dim.opacity(0.6))
                .pipGlow(drive.isConnected ? 0.45 : 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(drive.indexFolderName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Pip.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(drive.isConnected ? Pip.green.opacity(0.85) : Pip.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if drive.isConnected {
                StatusDot()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Pip.green.opacity(0.16) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Pip.green.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if drive.isCard {
            return "Card · \(drive.size)"
        }
        if drive.isConnected {
            parts.append("Connected")
        } else if let date = drive.lastConnected {
            parts.append(Fmt.relative.localizedString(for: date, relativeTo: Date()))
        }
        if !drive.lastUser.isEmpty { parts.append(drive.lastUser) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Missing index folder

struct MissingIndexView: View {
    @EnvironmentObject var store: IndexStore

    var body: some View {
        VStack(spacing: 16) {
            Text("Can't find the Drive Index folder")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Pip.text)
            Text("This app expects to live inside (or next to) your Drive Index folder — the one containing the \"Drive Indexer App\" folder. If you've moved it, just point the app to it.")
                .font(.system(size: 11.5))
                .foregroundStyle(Pip.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Choose Drive Index Folder…") { store.chooseIndexFolder() }
                .buttonStyle(PipButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
    }
}
