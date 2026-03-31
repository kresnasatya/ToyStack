import Engine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> some NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let w = view.window { onWindow(w) }
        }
        return view
    }
    func updateNSView(_ nsView: NSViewType, context: Context) {}
}

@main
struct ToyStack: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("ToyStack", id: "browser", for: UUID.self) { _ in
            BrowserView()
        }
    }
}

@MainActor
public struct BrowserView: View {
    @StateObject private var app = Browser()
    @Environment(\.openWindow) private var openWindow
    @State private var browserWindow: NSWindow?

    public init() {}

    public var body: some View {
        Canvas { ctx, size in
            if let tab = app.activeTab {
                let offset = app.chrome.bottom
                for item in app.drawList {
                    var c = ctx
                    c.translateBy(x: 0, y: offset - app.activeTabScroll)
                    if let cmd = item as? any PaintCommand {
                        cmd.execute(scroll: 0, context: &c)
                    } else if let ve = item as? Engine.VisualEffect {
                        ve.execute(context: &c)
                    }
                }
                for item in tab.scrollbarCommands() {
                    var c = ctx
                    c.translateBy(x: 0, y: offset)
                    if let cmd = item as? any PaintCommand {
                        cmd.execute(scroll: 0, context: &c)
                    } else if let ve = item as? Engine.VisualEffect {
                        ve.execute(context: &c)
                    }
                }
            }
            for cmd in app.chrome.paint() {
                cmd.execute(scroll: 0, context: &ctx)
            }
        }
        .background(app.darkMode ? Color.black : Color.white)
        .background(
            WindowReader { window in
                browserWindow = window
            }
        )
        .onAppear {
            NSEvent.addLocalMonitorForEvents(
                matching: .keyDown,
                handler: { [weak app] event in
                    guard event.window === browserWindow else { return event }
                    guard let app else { return event }
                    Task { @MainActor in
                        if event.modifierFlags.contains(.command) && event.keyCode == 45 {  // Cmd+N
                            openWindow(id: "browser", value: UUID())
                        } else if event.keyCode == 125 {  // Down arrow
                            app.activeTab?.scrollDown()
                        } else if event.keyCode == 126 {  // Up arrow
                            app.activeTab?.scrollUp()
                        } else if event.keyCode == 36 {  // Return
                            if !(await app.chrome.enter()) {
                                await app.activeTab?.enterKey()
                            }
                        } else if event.keyCode == 51 {
                            if app.chrome.backspace() {
                                app.objectWillChange.send()
                            }
                        } else if event.keyCode == 123 {  // left arrow
                            if app.chrome.cursorLeft() {
                                app.objectWillChange.send()
                            }
                        } else if event.keyCode == 124 {  // right arrow
                            if app.chrome.cursorRight() {
                                app.objectWillChange.send()
                            }
                        } else if event.keyCode == 48 {  // tab keyboard
                            if !(app.activeTab?.advanceTab() ?? false) {
                                app.chrome.focusAddressBar()
                                app.objectWillChange.send()
                            }
                        } else if event.modifierFlags.contains(.control) {
                            switch event.keyCode {
                            case 0:  // Ctrl+A
                                app.toggleAccessibility()
                            case 2:  // Ctrl+D
                                app.toggleDarkMode()
                                app.objectWillChange.send()
                            case 24:  // Ctrl+=
                                app.incrementZoom(true)
                            case 27:  // Ctrl+-
                                app.incrementZoom(false)
                            case 29:  // Ctrl+0
                                app.resetZoom()
                            default:
                                break
                            }
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
                    guard event.window === browserWindow else { return event }
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
            NSEvent.addLocalMonitorForEvents(
                matching: .otherMouseDown,
                handler: { [weak app] event in
                    guard event.window === browserWindow else { return event }
                    guard let app, event.buttonNumber == 2 else { return event }
                    Task { @MainActor in
                        let loc = event.locationInWindow
                        let x = loc.x
                        let y = app.windowSize.height - loc.y  // flip: AppKit y=0 is at bottom
                        guard y >= app.chrome.bottom else { return }
                        let tabY = y - app.chrome.bottom
                        if let linkURL = app.activeTab?.linkURL(at: x, y: tabY) {
                            await app.newTab(linkURL)
                        }
                    }
                    return nil
                }
            )
        }
        .onChange(
            of: (app.activeTab?.title ?? "ToyStack"),
            perform: { newTitle in
                NSApp.keyWindow?.title = newTitle
            }
        )
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
                            app.activeTab?.blur()
                            await app.chrome.click(x: x, y: y)
                            app.objectWillChange.send()
                        } else {
                            app.chrome.blur()
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
