import SwiftUI
import AppKit

struct DriveDetailView: View {
    let drive: DriveRecord
    @EnvironmentObject var store: IndexStore
    @State private var tab: Tab = .folders

    enum Tab: Hashable { case folders, history }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Pip.faint).frame(height: 1)
            tabs
            switch tab {
            case .folders: foldersList
            case .history: historyList
            }
        }
        .background(Pip.bg)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(drive.isConnected ? Pip.green : Pip.dim.opacity(0.6))
                        .pipGlow(drive.isConnected ? 0.45 : 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drive.indexFolderName)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Pip.text)
                        HStack(spacing: 6) {
                            if drive.isConnected {
                                StatusDot()
                                Text("Connected")
                                    .foregroundStyle(Pip.green)
                            } else {
                                Text("Not connected")
                                    .foregroundStyle(Pip.dim)
                            }
                        }
                        .font(.system(size: 11.5, weight: .medium))
                    }
                }
                Spacer()
                if let volume = drive.volumeURL {
                    HStack(spacing: 8) {
                        Button("Open Drive") {
                            NSWorkspace.shared.open(volume)
                        }
                        .buttonStyle(PipButtonStyle())
                        Button(store.ejectingID == drive.id ? "Ejecting…" : "⏏ Eject") {
                            store.eject(drive)
                        }
                        .buttonStyle(PipButtonStyle())
                        .disabled(store.ejectingID != nil)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                infoLine("Size", value(drive.size))
                infoLine("Free space", freeSpaceText)
                infoLine("Format", value(drive.format))
                infoLine("Last connected", lastConnectedText)
                infoLine("Last used by", value(drive.lastUser))
                usageBar
            }
        }
        .padding(16)
    }

    // How full the drive was when it was last measured.
    @ViewBuilder
    private var usageBar: some View {
        if let used = drive.usedPercent, used >= 0, used <= 100 {
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(Pip.faint)
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(used >= 90 ? Pip.amber : Pip.green)
                            .frame(width: max(2, geo.size.width * CGFloat(used) / 100))
                            .pipGlow(drive.isConnected ? 0.5 : 0)
                    }
                }
                .frame(width: 300, height: 7)
                Text("\(used)% used")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(used >= 90 ? Pip.amber : Pip.dim)
            }
            .padding(.top, 5)
        }
    }

    private func value(_ s: String) -> String {
        s.isEmpty || s == "unknown" ? "—" : s
    }

    private func infoLine(_ label: String, _ text: String) -> some View {
        HStack(spacing: 0) {
            Text(label.padding(toLength: 16, withPad: " ", startingAt: 0))
                .foregroundStyle(Pip.dim)
            Text(text)
                .foregroundStyle(Pip.text)
        }
        .font(.system(size: 11.5, design: .monospaced))
    }

    // Free space can only be measured while the drive is plugged in, so for
    // anything else this is the reading from its last connection.
    private var freeSpaceText: String {
        let free = value(drive.freeSpace)
        if free == "—" || drive.isConnected { return free }
        return "\(free)  (at last connection)"
    }

    private var lastConnectedText: String {
        guard !drive.lastConnectedString.isEmpty else { return "—" }
        if let date = drive.lastConnected {
            let rel = Fmt.relative.localizedString(for: date, relativeTo: Date())
            return "\(drive.lastConnectedString)  (\(rel))"
        }
        return drive.lastConnectedString
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 8) {
            tabButton("Contents", .folders)
            tabButton("History (\(drive.history.count))", .history)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func tabButton(_ title: String, _ target: Tab) -> some View {
        Button {
            tab = target
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tab == target ? Pip.green : Pip.dim)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(tab == target ? Pip.green.opacity(0.14) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(tab == target ? Pip.green.opacity(0.4) : Pip.faint, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Folders

    @ViewBuilder
    private var foldersList: some View {
        if drive.folderTree.isEmpty {
            PipEmpty(
                title: "Nothing indexed yet",
                message: "Either this drive is empty, or its contents couldn't be read. Connect it and press Rescan to try again."
            )
        } else {
            List(drive.folderTree, children: \.children) { node in
                HStack(spacing: 7) {
                    Image(systemName: node.isFile
                        ? "doc"
                        : (node.children == nil ? "folder" : "folder.fill"))
                        .font(.system(size: 11))
                        .foregroundStyle(Pip.dim)
                    Text(node.name)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(node.isFile ? Pip.text.opacity(0.8) : Pip.text)
                    Spacer(minLength: 12)
                    if let size = node.sizeLabel {
                        Text(size)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Pip.dim.opacity(0.75))
                    }
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                if !drive.foldersNote.isEmpty {
                    Text(drive.foldersNote)
                        .font(.system(size: 10))
                        .foregroundStyle(Pip.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Pip.bgRaised)
                        .overlay(Rectangle().fill(Pip.faint).frame(height: 1), alignment: .top)
                }
            }
        }
    }

    // MARK: History

    @ViewBuilder
    private var historyList: some View {
        if drive.history.isEmpty {
            PipEmpty(
                title: "No history yet",
                message: "Each time this drive is connected, the date and the user who was logged in are recorded here."
            )
        } else {
            List(drive.history) { entry in
                HStack(spacing: 10) {
                    Text(entry.dateString)
                        .foregroundStyle(Pip.dim)
                    Text(entry.user)
                        .fontWeight(.medium)
                        .foregroundStyle(Pip.text)
                    Spacer()
                    if entry.id == 0 {
                        Text("latest")
                            .foregroundStyle(Pip.green.opacity(0.8))
                    } else if let date = entry.date {
                        Text(Fmt.relative.localizedString(for: date, relativeTo: Date()))
                            .foregroundStyle(Pip.dim.opacity(0.7))
                    }
                }
                .font(.system(size: 11.5, design: .monospaced))
                .listRowSeparator(.hidden)
                .padding(.vertical, 1)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}
