import SwiftUI

@main
struct DriveIndexApp: App {
    init() {
        // Exits the process when the background helper launched us to scan.
        ScanSupport.runIfRequested()
    }

    @StateObject private var store = IndexStore()
    @StateObject private var updates = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(updates)
                .task { await updates.checkIfDue() }
        }
        .defaultSize(width: 920, height: 580)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updates.check(manual: true) }
                }
                .disabled(updates.installing)
            }
        }
    }
}
