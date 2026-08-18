import AppKit
import SwiftUI

@main
struct OtemanuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Otemanu is controlled directly from the island and does not install
        // a persistent menu-bar item.
        Settings {
            EmptyView()
        }
    }
}
