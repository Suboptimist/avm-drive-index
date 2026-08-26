import SwiftUI
import AppKit

struct CopyFailure: Identifiable {
    let id = UUID()
    let name: String
    let reason: String
}

/// Copies chosen files to a folder. Deliberately conservative: it never
/// overwrites anything already at the destination, never removes anything from
/// the source, and checks each copy's size before counting it as done.
@MainActor
final class CopyJob: ObservableObject {
    @Published var isRunning = false
    @Published var isFinished = false
    @Published var currentName = ""
    @Published var copiedCount = 0
    @Published var copiedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var totalCount = 0
    @Published var skipped: [String] = []
    @Published var failures: [CopyFailure] = []
    @Published var destination: URL?

    private var cancelRequested = false

    var progress: Double {
        totalBytes > 0 ? min(1, Double(copiedBytes) / Double(totalBytes)) : 0
    }

    func cancel() { cancelRequested = true }

    func start(files: [SourceFile], to folder: URL) {
        guard !isRunning else { return }
        isRunning = true
        isFinished = false
        cancelRequested = false
        copiedCount = 0
        copiedBytes = 0
        skipped = []
        failures = []
        destination = folder
        totalCount = files.count
        totalBytes = files.reduce(0) { $0 + $1.size }

        Task.detached { [weak self] in
            // Bind once: referring to the captured `self` var from inside the
            // nested closures below is an error under Swift 6.
            guard let job = self else { return }

            for file in files {
                if await job.cancelRequested { break }
                await MainActor.run { job.currentName = file.name }

                switch FileCopier.copyOne(file, into: folder) {
                case .copied(let bytes):
                    await MainActor.run {
                        job.copiedCount += 1
                        job.copiedBytes += bytes
                    }
                case .skippedExists:
                    await MainActor.run {
                        job.skipped.append(file.name)
                        job.copiedBytes += file.size
                    }
                case .failed(let reason):
                    await MainActor.run {
                        job.failures.append(CopyFailure(name: file.name, reason: reason))
                    }
                }
            }
            await MainActor.run {
                job.isRunning = false
                job.isFinished = true
                job.currentName = ""
            }
        }
    }
}

struct CopyFilesSheet: View {
    let volumeName: String
    let files: [SourceFile]
    let suggestedDestination: URL?

    @EnvironmentObject var store: IndexStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var job = CopyJob()

    @State private var chosen: Set<String> = []
    @State private var destination: URL?
    @State private var filter = ""

    private static let byteFmt: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false   // "0 bytes", not "Zero KB"
        return f
    }()

    private var visible: [SourceFile] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return files }
        return files.filter {
            $0.name.lowercased().contains(needle) || $0.folder.lowercased().contains(needle)
        }
    }

    private var selectedFiles: [SourceFile] { files.filter { chosen.contains($0.id) } }
    private var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(job.isRunning || job.isFinished ? "Copying from \(volumeName)"
                                                 : "Copy from \(volumeName)")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Pip.text)

            if job.isRunning || job.isFinished {
                progressBody
            } else {
                pickerBody
            }
        }
        .padding(18)
        .frame(width: 620, height: 540)
        .background(Pip.bgRaised)
        .onAppear { if destination == nil { destination = suggestedDestination } }
    }

    // MARK: Choosing

    private var pickerBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Filter by name or folder", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Pip.text)
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Pip.bg))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Pip.faint, lineWidth: 1))
                Button("Select all") { chosen.formUnion(visible.map(\.id)) }
                    .buttonStyle(PipButtonStyle())
                Button("None") { chosen.removeAll() }
                    .buttonStyle(PipButtonStyle())
            }

            if files.isEmpty {
                PipEmpty(title: "Nothing to copy",
                         message: "No readable files were found on \(volumeName).")
            } else {
                List {
                    ForEach(folders, id: \.self) { folder in
                        Section {
                            ForEach(visible.filter { $0.folder == folder }) { file in
                                row(for: file)
                            }
                        } header: {
                            Text(folder.isEmpty ? "Top level" : folder)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Pip.dim)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Copy into")
                    .font(.system(size: 11))
                    .foregroundStyle(Pip.dim)
                HStack(spacing: 8) {
                    Text(destination.map(friendly) ?? "Choose a folder on another drive…")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(destination == nil ? Pip.dim : Pip.text)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…", action: chooseDestination)
                        .buttonStyle(PipButtonStyle())
                }
            }

            HStack {
                Text("\(chosen.count) of \(files.count) selected · \(Self.byteFmt.string(fromByteCount: selectedBytes))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Pip.dim)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PipButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Copy") { if let destination { job.start(files: selectedFiles, to: destination) } }
                    .buttonStyle(PipButtonStyle())
                    .disabled(chosen.isEmpty || destination == nil)
            }
        }
    }

    private var folders: [String] {
        var seen: [String] = []
        for file in visible where !seen.contains(file.folder) { seen.append(file.folder) }
        return seen
    }

    private func row(for file: SourceFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: chosen.contains(file.id) ? "checkmark.square.fill" : "square")
                .foregroundStyle(chosen.contains(file.id) ? Pip.green : Pip.dim)
            Text(file.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Pip.text)
                .lineLimit(1)
            Spacer(minLength: 10)
            Text(Self.byteFmt.string(fromByteCount: file.size))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Pip.dim)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if chosen.contains(file.id) { chosen.remove(file.id) } else { chosen.insert(file.id) }
        }
        .listRowSeparator(.hidden)
    }

    private func friendly(_ url: URL) -> String {
        url.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.message = "Where should these files go?"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination ?? suggestedDestination
        if panel.runModal() == .OK { destination = panel.url }
    }

    // MARK: Copying

    private var progressBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if job.isRunning {
                Text(job.currentName.isEmpty ? "Starting…" : job.currentName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Pip.text)
                    .lineLimit(1)
            }
            ProgressView(value: job.progress)
                .tint(Pip.green)
            Text("\(job.copiedCount) of \(job.totalCount) copied · "
                 + "\(Self.byteFmt.string(fromByteCount: job.copiedBytes)) of "
                 + Self.byteFmt.string(fromByteCount: job.totalBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Pip.dim)

            if job.isFinished {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !job.skipped.isEmpty {
                            Text("Skipped — already at the destination (\(job.skipped.count))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Pip.amber)
                            Text(job.skipped.joined(separator: ", "))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Pip.dim)
                        }
                        if !job.failures.isEmpty {
                            Text("Failed (\(job.failures.count))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Pip.amber)
                            ForEach(job.failures) { failure in
                                Text("\(failure.name) — \(failure.reason)")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Pip.dim)
                            }
                        }
                        if job.skipped.isEmpty && job.failures.isEmpty {
                            Text("Every file copied and checked.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Pip.green)
                        }
                        Text("Nothing was removed from \(volumeName).")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Pip.dim)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer()
            }

            HStack {
                Spacer()
                if job.isRunning {
                    Button("Stop") { job.cancel() }
                        .buttonStyle(PipButtonStyle())
                } else {
                    if let folder = job.destination {
                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                        }
                        .buttonStyle(PipButtonStyle())
                    }
                    Button("Done") {
                        store.rescan()
                        dismiss()
                    }
                    .buttonStyle(PipButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
