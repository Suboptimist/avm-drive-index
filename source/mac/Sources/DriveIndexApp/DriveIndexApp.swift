import SwiftUI

@main
struct DriveIndexApp: App {
    init() {
        // Exits the process when the background helper launched us to scan.
        ScanSupport.runIfRequested()
    }

    @StateObject private var store = IndexStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .defaultSize(width: 920, height: 580)
    }
}
