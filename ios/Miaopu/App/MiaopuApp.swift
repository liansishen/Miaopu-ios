import SwiftUI

@main
struct MiaopuApp: App {
    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting-reset") {
            UserDefaults.standard.removeObject(forKey: "subscribedSports")
        }
    }
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
