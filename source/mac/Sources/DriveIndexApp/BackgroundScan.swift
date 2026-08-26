import Foundation

/// Support for scanning outside the UI.
///
/// The background helper used to run `/bin/bash drive_indexer.sh` directly.
/// macOS then attributed the drive access to a bare shell, which is not
/// something the user can grant permission to, so folder and file listings on
/// external drives came back empty ("could not read this drive's contents")
/// while size, free space and history still worked.
///
/// The helper now launches this app with `--scan` instead. The access is then
/// attributed to the app, which appears in System Settings → Privacy &
/// Security and can be granted access once.
enum ScanSupport {

    static let scanArgument = "--scan"

    static var defaultIndexFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AVM Drive Index")
    }

    /// Where the index lives, resolved without touching the UI layer.
    static func resolveIndexFolder() -> URL {
        if let fromEnvironment = ProcessInfo.processInfo.environment["DRIVE_INDEX_DIR"],
           !fromEnvironment.isEmpty {
            return URL(fileURLWithPath: fromEnvironment)
        }
        if let saved = UserDefaults.standard.string(forKey: "indexFolderPath") {
            let url = URL(fileURLWithPath: saved)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return defaultIndexFolder
    }

    /// The scanner is copied into the index folder so the helper keeps working
    /// even if the app is moved or deleted. That copy has to be refreshed when
    /// the app is updated, or an updated app would go on running the scanner it
    /// originally shipped with.
    @discardableResult
    static func syncScript(into indexFolder: URL) -> URL? {
        let fm = FileManager.default
        let installed = indexFolder.appendingPathComponent("drive_indexer.sh")
        guard let bundled = Bundle.main.resourceURL?
                .appendingPathComponent("Drive Indexer Support/drive_indexer.sh"),
              let shipped = try? Data(contentsOf: bundled)
        else { return fm.fileExists(atPath: installed.path) ? installed : nil }

        guard fm.fileExists(atPath: indexFolder.path) else { return nil }
        if let current = try? Data(contentsOf: installed), current == shipped {
            return installed
        }
        do {
            try shipped.write(to: installed)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installed.path)
        } catch {
            return fm.fileExists(atPath: installed.path) ? installed : nil
        }
        return installed
    }

    /// Runs one scan and exits, when launched with `--scan`. Returns normally
    /// for an ordinary launch so the window opens as usual.
    static func runIfRequested() {
        guard CommandLine.arguments.contains(scanArgument) else { return }

        let indexFolder = resolveIndexFolder()
        guard let script = syncScript(into: indexFolder) else { exit(0) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["DRIVE_INDEX_DIR"] = indexFolder.path
        process.environment = environment

        do {
            try process.run()
        } catch {
            exit(1)
        }
        process.waitUntilExit()
        exit(process.terminationStatus)
    }
}
