import SwiftUI

@main
struct DriveIndexApp: App {
    @StateObject private var store = IndexStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .defaultSize(width: 920, height: 580)
    }
}
