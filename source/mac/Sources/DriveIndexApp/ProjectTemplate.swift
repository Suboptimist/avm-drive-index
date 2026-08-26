import Foundation

/// Creates the standard project folder layout on a drive.
///
/// This is the "AVM Folder Structure" Automator app built into the app: it
/// asked for a project name and a destination, then made the same folders.
enum ProjectTemplate {

    /// Created in this order. Parents are made automatically, but they are
    /// listed explicitly so the sheet can show exactly what will appear.
    static let folders = [
        "01_Project Files",
        "01_Project Files/01_Davinci Resolve",
        "01_Project Files/02_Premiere",
        "01_Project Files/03_After Effects",
        "02_Footage",
        "03_Graphics",
        "04_Music",
        "05_Docs",
        "06_Exports",
    ]

    /// Top-level folders only, for the summary in the sheet.
    static var topLevelFolders: [String] {
        folders.filter { !$0.contains("/") }
    }

    /// Why this name cannot be used, or nil when it is fine.
    static func rejectionReason(for rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Enter a project name." }
        if name.hasPrefix(".") { return "A name starting with a dot would be hidden." }
        if name.contains("/") { return "A name cannot contain a slash." }
        if name.contains(":") { return "A name cannot contain a colon." }
        if name.count > 200 { return "That name is too long." }
        return nil
    }

    enum CreateError: LocalizedError {
        case alreadyExists(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyExists(let name):
                return "\"\(name)\" already exists in that location."
            case .failed(let reason):
                return reason
            }
        }
    }

    /// Makes the project folder and its subfolders. Never touches anything that
    /// is already there: an existing folder of the same name is an error rather
    /// than something to merge into.
    @discardableResult
    static func create(named rawName: String, in parent: URL) throws -> URL {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = parent.appendingPathComponent(name, isDirectory: true)
        let fm = FileManager.default

        if fm.fileExists(atPath: root.path) {
            throw CreateError.alreadyExists(name)
        }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            for folder in folders {
                try fm.createDirectory(at: root.appendingPathComponent(folder, isDirectory: true),
                                       withIntermediateDirectories: true)
            }
        } catch {
            throw CreateError.failed(error.localizedDescription)
        }
        return root
    }
}
