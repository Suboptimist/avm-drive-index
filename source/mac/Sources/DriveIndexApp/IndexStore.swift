import SwiftUI
import AppKit

@MainActor
final class IndexStore: ObservableObject {
    @Published var drives: [DriveRecord] = []
    @Published var indexFolder: URL?
    @Published var isRescanning = false
    @Published var watcherInstalled = true
    @Published var lastUpdated: Date?
    @Published var pendingDelete: DriveRecord?
    @Published var ejectingID: String?
    @Published var ejectError: String?
    @Published var org = Organization()
    @Published var cards: [DriveRecord] = []

    /// Walking a card is not free, so its files and tree are kept until the
    /// card is unplugged or a rescan is asked for.
    private var cardCache: [String: (files: [SourceFile], tree: [FolderNode])] = [:]

    private var dirWatcher: DispatchSourceFileSystemObject?
    private var watchedFD: CInt = -1
    private var refreshTimer: Timer?

    private static let agentPlist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.avm.drive-indexer.plist")
    private static let defaultIndexFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AVM Drive Index")

    init() {
        indexFolder = Self.locateIndexFolder()
        syncIndexerScript()
        loadOrg()
        reload()
        checkWatcher()
        startWatchingIndexFolder()

        // When a drive is plugged in or ejected while the app is open,
        // rescan right away (the background helper does this too, but this
        // makes the window update instantly).
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload(); self?.rescan() }
        }
        nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload(); self?.rescan() }
        }

        // Gentle safety net so the window never shows stale data for long.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    // MARK: - Keeping the installed scanner current

    /// The scanner is copied into the index folder so the background helper
    /// keeps working even if the app is moved or deleted. That copy has to be
    /// refreshed whenever the app is updated, otherwise an updated app would go
    /// on running the scanner it shipped with originally.
    private func syncIndexerScript() {
        guard let root = indexFolder else { return }
        ScanSupport.syncScript(into: root)
    }

    // MARK: - Finding the Drive Index folder

    static func locateIndexFolder() -> URL? {
        let fm = FileManager.default
        if let saved = UserDefaults.standard.string(forKey: "indexFolderPath") {
            let savedURL = URL(fileURLWithPath: saved)
            if fm.fileExists(atPath: savedURL.path) { return savedURL }
        }
        if fm.fileExists(atPath: defaultIndexFolder.path) {
            return defaultIndexFolder
        }
        var candidates: [URL] = []
        let bundleDir = Bundle.main.bundleURL.deletingLastPathComponent()
        candidates.append(bundleDir)                           // app next to "Drives"
        candidates.append(bundleDir.deletingLastPathComponent())
        candidates.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Drive Index"))

        for c in candidates where fm.fileExists(
            atPath: c.appendingPathComponent("Drive Indexer App/drive_indexer.sh").path
        ) {
            return c
        }
        // A new installation has no data yet. Return the standard private
        // location so the "Turn On" action can create it.
        return defaultIndexFolder
    }

    func chooseIndexFolder() {
        let panel = NSOpenPanel()
        panel.message = "Choose your Drive Index data folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: "indexFolderPath")
        indexFolder = url
        loadOrg()
        reload()
        checkWatcher()
        startWatchingIndexFolder()
    }

    private var indexerScript: URL? {
        indexFolder?.appendingPathComponent("drive_indexer.sh")
    }

    // MARK: - Loading the index

    func reload() {
        guard let root = indexFolder else { drives = []; return }
        let drivesDir = root.appendingPathComponent("Drives")
        let fm = FileManager.default

        // What is actually mounted right now (ground truth, straight from
        // the system — never stale).
        var mounted: [(url: URL, name: String, uuid: String?)] = []
        for entry in (try? fm.contentsOfDirectory(atPath: "/Volumes")) ?? [] {
            let url = URL(fileURLWithPath: "/Volumes").appendingPathComponent(entry)
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                continue   // skip the "Macintosh HD" symlink to /
            }
            let vals = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .isVolumeKey])
            guard vals?.isVolume == true else { continue }   // ignore leftover empty mount-point folders
            mounted.append((url, entry, vals?.volumeUUIDString))
        }
        func mountedVolume(uuid: String?, name: String) -> URL? {
            if let uuid,
               let hit = mounted.first(where: { $0.uuid?.caseInsensitiveCompare(uuid) == .orderedSame }) {
                return hit.url
            }
            return mounted.first(where: { $0.name == name })?.url
        }

        var records: [DriveRecord] = []
        let folders = (try? fm.contentsOfDirectory(
            at: drivesDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        for folder in folders {
            let info = folder.appendingPathComponent("_DRIVE INFO.txt")
            guard fm.fileExists(atPath: info.path),
                  let record = InfoFileParser.parse(infoFile: info, folderURL: folder, mountedVolume: mountedVolume)
            else { continue }
            records.append(record)
        }
        // Connected drives first, then most recently connected.
        drives = records.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            return ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast)
        }
        reloadCards()
        lastUpdated = Date()
        reconcileOrg()
    }

    // MARK: - Memory cards (never catalogued, shown while mounted)

    private func reloadCards() {
        var records: [DriveRecord] = []
        for card in CardVolumes.connected() {
            let key = card.url.path
            if cardCache[key] == nil {
                let files = CardVolumes.files(at: card.url)
                cardCache[key] = (files, CardVolumes.tree(from: files, rootPath: key))
            }
            guard let cached = cardCache[key] else { continue }
            records.append(DriveRecord(
                id: key,
                indexFolderName: card.name,
                name: card.name,
                size: CardVolumes.sizeText(card.sizeBytes),
                freeSpace: CardVolumes.freeText(size: card.sizeBytes, free: card.freeBytes),
                usedPercent: CardVolumes.usedPercent(size: card.sizeBytes, free: card.freeBytes),
                format: card.format,
                uuid: nil,
                lastConnected: nil,
                lastConnectedString: "",
                lastUser: "",
                foldersNote: "\(cached.files.count) files on the card",
                history: [],
                folderURL: card.url,
                volumeURL: card.url,
                isCard: true,
                folderTree: cached.tree))
        }
        cards = records

        // Forget cards that have been taken out.
        let mounted = Set(records.map(\.id))
        for key in cardCache.keys where !mounted.contains(key) { cardCache.removeValue(forKey: key) }
    }

    /// The files on a card, for the copy sheet.
    func sourceFiles(for record: DriveRecord) -> [SourceFile] {
        if let cached = cardCache[record.id] { return cached.files }
        guard let volume = record.volumeURL else { return [] }
        return CardVolumes.files(at: volume)
    }

    /// Any record the sidebar can select, drive or card.
    func record(withID id: String) -> DriveRecord? {
        drives.first { $0.id == id } ?? cards.first { $0.id == id }
    }

    // MARK: - Rescanning (runs the same script the background helper uses)

    func rescan() {
        cardCache.removeAll()      // pick up anything newly written to a card
        guard let script = indexerScript, let root = indexFolder, !isRescanning else { return }
        isRescanning = true
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment
        env["DRIVE_INDEX_DIR"] = root.path
        proc.environment = env
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isRescanning = false
                self?.reload()
            }
        }
        do {
            try proc.run()
        } catch {
            isRescanning = false
        }
    }

    // MARK: - Eject

    func eject(_ drive: DriveRecord) {
        guard let volume = drive.volumeURL, ejectingID == nil else { return }
        ejectingID = drive.id
        Task.detached {
            var failure: String?
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            } catch {
                failure = error.localizedDescription
            }
            await MainActor.run { [failure] in
                self.ejectingID = nil
                self.ejectError = failure
                self.reload()   // flip the connection state immediately
                self.rescan()
            }
        }
    }

    // MARK: - Removing a drive from the index

    func deleteIndex(_ drive: DriveRecord) {
        try? FileManager.default.trashItem(at: drive.folderURL, resultingItemURL: nil)
        reload()
        rescan()   // rebuilds the overview file (and re-indexes the drive if it's still connected)
    }

    // MARK: - Background helper (LaunchAgent)

    func checkWatcher() {
        watcherInstalled = FileManager.default.fileExists(atPath: Self.agentPlist.path)
    }

    func installWatcher() {
        guard let root = indexFolder else { return }
        guard let installer = Bundle.main.resourceURL?
            .appendingPathComponent("Drive Indexer Support/Install Drive Indexer.command")
        else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [installer.path]
        let destination: URL
        if let saved = UserDefaults.standard.string(forKey: "indexFolderPath") {
            destination = URL(fileURLWithPath: saved)
        } else {
            destination = Self.defaultIndexFolder
        }
        var env = ProcessInfo.processInfo.environment
        env["DRIVE_INDEX_DIR"] = destination.path
        env["LEGACY_INDEX_DIR"] = root.path
        proc.environment = env
        indexFolder = destination
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.checkWatcher()
                self?.reload()
                self?.startWatchingIndexFolder()
            }
        }
        try? proc.run()
    }

    // MARK: - Auto-refresh when the background helper updates the index

    private func startWatchingIndexFolder() {
        dirWatcher?.cancel()   // its cancel handler closes the old descriptor
        dirWatcher = nil
        watchedFD = -1

        guard let root = indexFolder else { return }
        // The overview file is rewritten on every indexing pass, so watching
        // the index folder itself catches every update.
        let fd = open(root.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        dirWatcher = source
    }
}
