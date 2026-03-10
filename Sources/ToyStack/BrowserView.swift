import Core
import SwiftUI

@MainActor
public struct BrowserView: View {
    @StateObject private var app = BrowserApp()

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
                        } else if event.keyCode == 36 {  // Return
                            await app.chrome.enter()
                        } else if let char = event.characters, !char.isEmpty {
                            let scalar = char.unicodeScalars.first!.value
                            if scalar >= 0x20 && scalar < 0x7F {
                                if !app.chrome.keypress(char) {
                                    app.activeTab?.keypress(char)
                                }
                            }
                        }
                    }
                    return nil  // consume the event
                })
        }
        .frame(width: WIDTH, height: HEIGHT)
        .task {
            await app.newTab(WebURL("https://browser.engineering"))
        }
    }
}
