import Engine
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
        }
    }
}

@MainActor
public struct BrowserView: View {
    @StateObject private var app = Browser()

    public init() {}

    public var body: some View {
        Canvas { ctx, size in
            if let tab = app.activeTab {
                let offset = app.chrome.bottom
                for (cmd, scroll) in tab.visibleCommands(offset: offset) {
                    var c = ctx
                    c.translateBy(x: 0, y: offset)
                    cmd.execute(scroll: scroll, context: &c)
                }
            }
            for cmd in app.chrome.paint() {
                cmd.execute(scroll: 0, context: &ctx)
            }
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(
                matching: .keyDown,
                handler: { [weak app] event in
                    guard let app else { return event }
                    Task { @MainActor in
                        if event.keyCode == 125 {  // Down arrow
                            app.activeTab?.scrollDown()
                        } else if event.keyCode == 126 {  // Up arrow
                            app.activeTab?.scrollUp()
                        } else if event.keyCode == 36 {  // Return
                            await app.chrome.enter()
                        } else if let char = event.characters, !char.isEmpty {
                            let scalar = char.unicodeScalars.first!.value
                            if scalar >= 0x20 && scalar < 0x7F {
                                if !app.chrome.keypress(char) {
                                    app.activeTab?.keypress(char)
                                } else {
                                    app.objectWillChange.send()
                                }
                            }
                        }
                    }
                    return nil  // consume the event
                }
            )
            NSEvent.addLocalMonitorForEvents(
                matching: .scrollWheel,
                handler: { [weak app] event in
                    guard let app else { return event }
                    Task { @MainActor in
                        if event.scrollingDeltaY > 0 {
                            app.activeTab?.scrollUp()
                        } else if event.scrollingDeltaY < 0 {
                            app.activeTab?.scrollDown()
                        }
                    }
                    return nil
                }
            )
        }
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { newSize in
            app.resize(to: newSize)
        }
        .gesture(
            SpatialTapGesture()
                .onEnded({ value in
                    Task { @MainActor in
                        let x = value.location.x
                        let y = value.location.y
                        if y < app.chrome.bottom {
                            await app.chrome.click(x: x, y: y)
                            app.objectWillChange.send()
                        } else {
                            await app.activeTab?.click(x: x, y: y - app.chrome.bottom)
                        }
                    }
                })
        )
        .task {
            await app.newTab(WebURL("https://browser.engineering"))
        }
    }
}
