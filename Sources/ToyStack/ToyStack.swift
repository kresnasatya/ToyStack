import Core
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct ToyStack: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("ToyStack", id: "main") {
            BrowserView()
                .frame(width: WIDTH, height: HEIGHT)
        }
        .windowResizability(.contentSize)
    }
}
