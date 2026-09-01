import Foundation
import SwiftUI
import AppKit

/// Checks GitHub Releases for a newer AVM Drive Index and installs it in
/// place. Quiet by design: the automatic check never interrupts unless an
/// update actually exists, and every failure path degrades to "no update
/// offered" rather than an error the user has to dismiss.
@MainActor
final class UpdateChecker: ObservableObject {

    struct Prompt: Identifiable {
        enum Kind { case updateAvailable, info }
        let id = UUID()
        let kind: Kind
        let title: String
        let message: String
    }

    @Published var prompt: Prompt?
    @Published var installing = false

    private var pendingAsset: (version: String, downloadURL: URL)?

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Checking

    /// Launch-time check, at most once a day.
    func checkIfDue() async {
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        guard Date().timeIntervalSince1970 - last > 20 * 3600 else { return }
        await check(manual: false)
    }

    func check(manual: Bool) async {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")

        var request = URLRequest(url: UpdateConfig.releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]] else {
                throw URLError(.badServerResponse)
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard VersionCompare.isNewer(latest, than: Self.currentVersion) else {
                if manual {
                    prompt = Prompt(kind: .info, title: "You're Up to Date",
                                    message: "AVM Drive Index \(Self.currentVersion) is the newest version.")
                }
                return
            }
            // The repository is public, so the plain browser_download_url works
            // and no authorisation header is involved anywhere.
            guard let zip = assets.first(where: { ($0["name"] as? String) == UpdateConfig.macAsset }),
                  let urlString = zip["browser_download_url"] as? String,
                  let assetURL = URL(string: urlString) else {
                if manual {
                    prompt = Prompt(kind: .info, title: "Update Found, but…",
                                    message: "Version \(latest) exists but has no \(UpdateConfig.macAsset) attached. Re-publish the release.")
                }
                return
            }
            pendingAsset = (latest, assetURL)
            prompt = Prompt(kind: .updateAvailable, title: "AVM Drive Index \(latest) Is Available",
                            message: "You have \(Self.currentVersion). The update downloads and relaunches the app automatically — your drive index is untouched.")
        } catch {
            if manual {
                prompt = Prompt(kind: .info, title: "Couldn't Check for Updates",
                                message: "Are you online? (\(error.localizedDescription))")
            }
        }
    }

    // MARK: - Installing

    func installUpdate() {
        guard let asset = pendingAsset, !installing else { return }
        installing = true
        Task {
            do {
                try await Self.download(asset: asset, replacing: Bundle.main.bundleURL)
                // Success relaunches the app; we only reach here on a fallback.
            } catch let fallback as InstallFallback {
                installing = false
                NSWorkspace.shared.activateFileViewerSelecting([fallback.newApp])
                prompt = Prompt(kind: .info, title: "One Manual Step",
                                message: "The new version was downloaded (shown in Finder). Quit AVM Drive Index, then drag the new one into your Applications folder to replace it.")
            } catch {
                installing = false
                prompt = Prompt(kind: .info, title: "Update Failed",
                                message: error.localizedDescription)
            }
        }
    }

    private struct InstallFallback: Error { let newApp: URL }

    private nonisolated static func download(asset: (version: String, downloadURL: URL),
                                             replacing current: URL) async throws {
        let (tempFile, response) = try await URLSession.shared.download(from: asset.downloadURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "AVMDriveIndex", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The download didn't complete. Try again later."])
        }

        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("drive-index-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent(UpdateConfig.macAsset)
        try fm.moveItem(at: tempFile, to: zip)

        try run("/usr/bin/ditto", "-xk", zip.path, work.path)
        let newApp = work.appendingPathComponent("AVM Drive Index.app")
        guard fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/DriveIndexApp").path) else {
            throw NSError(domain: "AVMDriveIndex", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The downloaded update looks incomplete."])
        }
        // Downloaded by the app itself, but clear quarantine defensively so the
        // replaced app never triggers a Gatekeeper re-approval.
        try? run("/usr/bin/xattr", "-dr", "com.apple.quarantine", newApp.path)

        // Swap in place. If we are running from somewhere unwritable (a DMG, a
        // translocated path), fall back to showing the new app in Finder.
        guard current.pathExtension == "app",
              !current.path.contains("/AppTranslocation/"),
              fm.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            throw InstallFallback(newApp: newApp)
        }
        let backup = fm.temporaryDirectory
            .appendingPathComponent("AVM-Drive-Index-old-\(UUID().uuidString).app")
        try fm.moveItem(at: current, to: backup)
        do {
            try fm.moveItem(at: newApp, to: current)
        } catch {
            try? fm.moveItem(at: backup, to: current)   // put the old app back
            throw error
        }

        try run("/usr/bin/open", "-n", current.path)
        await MainActor.run { NSApp.terminate(nil) }
    }

    private nonisolated static func run(_ tool: String, _ args: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AVMDriveIndex", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "\((tool as NSString).lastPathComponent) failed."])
        }
    }
}
