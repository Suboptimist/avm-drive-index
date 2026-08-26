import SwiftUI
import AppKit

struct NewProjectSheet: View {
    let drive: DriveRecord
    @EnvironmentObject var store: IndexStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = "My Project"
    @State private var location: URL
    @State private var problem: String?

    init(drive: DriveRecord) {
        self.drive = drive
        _location = State(initialValue: drive.volumeURL ?? drive.folderURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Project")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Pip.text)

            VStack(alignment: .leading, spacing: 5) {
                Text("Project name")
                    .font(.system(size: 11))
                    .foregroundStyle(Pip.dim)
                TextField("", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Pip.text)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Pip.bg))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Pip.faint, lineWidth: 1))
                    .onSubmit(create)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Create it in")
                    .font(.system(size: 11))
                    .foregroundStyle(Pip.dim)
                HStack(spacing: 8) {
                    Text(friendlyLocation)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Pip.text)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…", action: chooseLocation)
                        .buttonStyle(PipButtonStyle())
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Folders created")
                    .font(.system(size: 11))
                    .foregroundStyle(Pip.dim)
                Text(ProjectTemplate.topLevelFolders.joined(separator: "   "))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Pip.dim)
                Text("01_Project Files also gets Davinci Resolve, Premiere and After Effects.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Pip.dim.opacity(0.8))
            }

            if let problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Pip.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PipButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .buttonStyle(PipButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 460)
        .background(Pip.bgRaised)
    }

    private var friendlyLocation: String {
        location.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.message = "Where should the project folder go?"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = location
        if panel.runModal() == .OK, let chosen = panel.url {
            location = chosen
            problem = nil
        }
    }

    private func create() {
        if let reason = ProjectTemplate.rejectionReason(for: name) {
            problem = reason
            return
        }
        do {
            let created = try ProjectTemplate.create(named: name, in: location)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: created.path)
            store.rescan()          // so the new folders show up in the index
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}
