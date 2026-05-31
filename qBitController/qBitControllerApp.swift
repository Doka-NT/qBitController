import SwiftUI

@main
struct qBitControllerApp: App {
    @StateObject private var client = QBittorrentClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
        }
    }
}
