import Engine
import SwiftUI

extension Browser: TabManager {}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Tab.showAlert = { title, message in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        Tab.showConfirm = { title, message in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "Resubmit")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
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
    private let bookmarks = Bookmarks()

    var body: some Scene {
        WindowGroup("ToyStack", id: "browser", for: UUID.self) { _ in
            BrowserView(bookmarks: bookmarks)
        }
    }
}

@MainActor
public struct BrowserView: View {
    @StateObject private var app = Browser()
    @State private var chrome = Chrome()
    @Environment(\.openWindow) private var openWindow
    @State private var browserWindow: NSWindow?
    let bookmarks: Bookmarks

    init(bookmarks: Bookmarks) {
        self.bookmarks = bookmarks
    }

    public var body: some View {
        Canvas { ctx, size in
            if let tab = app.activeTab {
                let offset = chrome.bottom
                for item in app.drawList {
                    let r = SwiftUIRenderer(context: ctx)
                    r.translateBy(x: 0, y: offset - app.activeTabScroll)
                    if let cmd = item as? any PaintCommand {
                        cmd.execute(scroll: 0, renderer: r)
                    } else if let ve = item as? Engine.VisualEffect {
                        ve.execute(renderer: r)
                    }
                }
                for item in tab.scrollbarCommands() {
                    let r = SwiftUIRenderer(context: ctx)
                    r.translateBy(x: 0, y: offset)
                    if let cmd = item as? any PaintCommand {
                        cmd.execute(scroll: 0, renderer: r)
                    } else if let ve = item as? Engine.VisualEffect {
                        ve.execute(renderer: r)
                    }
                }
            }
            let chromeRenderer = SwiftUIRenderer(context: ctx)
            for cmd in chrome.paint() {
                cmd.execute(scroll: 0, renderer: chromeRenderer)
            }
        }
        .background(app.commitedForcedColors ? Color(engine: EngineColor(cssName: ForcedColor.canvas)) : (app.commitedPrefersDark ? Color.black : Color.white))
        .background(
            WindowReader { window in
                browserWindow = window
            }
        )
        .onAppear {
            NSEvent.addLocalMonitorForEvents(
                matching: .keyDown,
                handler: { [weak app, chrome] event in
                    guard event.window === browserWindow else { return event }
                    guard let app else { return event }
                    Task { @MainActor in
                        if event.modifierFlags.contains(.command) && event.keyCode == 45 {  // Cmd+N
                            openWindow(id: "browser", value: UUID())
                        } else if event.modifierFlags.contains(.command) && event.keyCode == 123 {  // Cmd+Left -> go back
                            app.activeTab?.goBack()
                        } else if event.keyCode == 125 {  // Down arrow
                            print(
                                "[key] down arrow hasScrollElement=\(app.activeTab?.hasScrollElement ?? false)"
                            )
                            if let tab = app.activeTab, tab.hasScrollElement {
                                tab.scrollElementDown()
                            } else {
                                app.activeTab?.scrollDown()
                            }
                        } else if event.keyCode == 126 {  // Up arrow
                            if let tab = app.activeTab, tab.hasScrollElement {
                                tab.scrollElementUp()
                            } else {
                                app.activeTab?.scrollUp()
                            }
                        } else if event.keyCode == 36 {  // Return
                            if !(chrome.enter()) {
                                app.activeTab?.enterKey()
                            }
                        } else if event.keyCode == 51 {
                            if chrome.backspace() {
                                app.objectWillChange.send()
                            }
                        } else if event.keyCode == 123 {  // left arrow
                            if chrome.cursorLeft() {
                                app.objectWillChange.send()
                            }
                        } else if event.keyCode == 124 {  // right arrow
                            if chrome.cursorRight() {
                                app.objectWillChange.send()
                            }
                        } else if event.keyCode == 48 {  // tab keyboard
                            if event.modifierFlags.contains(.control) {
                                app.cycleTabs()
                            } else {
                                if chrome.hasFocus {
                                    chrome.blur()
                                    app.activeTab?.advanceTab()
                                } else if !(app.activeTab?.advanceTab() ?? false) {
                                    chrome.focusAddressBar()
                                }
                                app.objectWillChange.send()
                            }
                        } else if event.modifierFlags.contains(.control) {
                            switch event.keyCode {
                            case 0:  // Ctrl+A
                                app.toggleAccessibility()
                            case 1:  // Ctrl+S
                                app.advanceAccessibility()
                            case 2:  // Ctrl+D
                                app.togglePrefersDark()
                            case 4:  // Ctrl+H
                                app.toggleForcedColors()
                            case 12:
                                NSApplication.shared.terminate(nil)
                            case 17:
                                app.newTab(WebURL("about:blank"))
                            case 24:  // Ctrl+=
                                app.incrementZoom(true)
                            case 27:  // Ctrl+-
                                app.incrementZoom(false)
                            case 29:  // Ctrl+0
                                app.resetZoom()
                            case 37:  // Ctrl+L
                                app.activeTab?.blur()
                                chrome.focusAddressBar()
                                app.objectWillChange.send()
                            default:
                                break
                            }
                        } else if let char = event.characters, !char.isEmpty {
                            let scalar = char.unicodeScalars.first!.value
                            if scalar >= 0x20 && scalar < 0x7F {
                                if !chrome.keypress(char) {
                                    app.activeTab?.keypress(char)
                                } else {
                                    app.objectWillChange.send()
                                }
                            }
                        }
                    }
                    return nil
                }
            )
            NSEvent.addLocalMonitorForEvents(
                matching: .scrollWheel,
                handler: { [weak app, chrome] event in
                    guard event.window === browserWindow else { return event }
                    guard let app else { return event }
                    Task { @MainActor in
                        guard event.scrollingDeltaY != 0 else { return }
                        let loc = event.locationInWindow
                        let x = loc.x
                        let screenY = app.windowSize.height - loc.y
                        let contentY = screenY - chrome.bottom
                        if contentY > 0 {
                            app.activeTab?.scrollAt(
                                x: x, y: contentY, deltaY: event.scrollingDeltaY)
                        } else if event.scrollingDeltaY > 0 {
                            app.activeTab?.scrollUp()
                        } else {
                            app.activeTab?.scrollDown()
                        }
                    }
                    return nil
                }
            )
            NSEvent.addLocalMonitorForEvents(
                matching: .otherMouseDown,
                handler: { [weak app, chrome] event in
                    guard event.window === browserWindow else { return event }
                    guard let app, event.buttonNumber == 2 else { return event }
                    Task { @MainActor in
                        let loc = event.locationInWindow
                        let x = loc.x
                        let y = app.windowSize.height - loc.y
                        guard y >= chrome.bottom else { return }
                        let tabY = y - chrome.bottom
                        if let linkURL = app.activeTab?.linkURL(at: x, y: tabY) {
                            app.newTab(linkURL)
                        }
                    }
                    return nil
                }
            )
            NSEvent.addLocalMonitorForEvents(
                matching: .mouseMoved,
                handler: { [weak app, chrome] event in
                    guard event.window === browserWindow else { return event }
                    guard let app else { return event }
                    Task { @MainActor in
                        let loc = event.locationInWindow
                        let x = loc.x
                        let y = app.windowSize.height - loc.y
                        guard y >= chrome.bottom else { return }
                        let tabY = y - chrome.bottom
                        app.handleHover(x: x, y: tabY)
                    }
                    return event
                })
        }
        .onChange(
            of: (app.activeTab?.title ?? "ToyStack"),
            perform: { newTitle in
                NSApp.keyWindow?.title = newTitle
            }
        )
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { newSize in
            app.resize(to: newSize)
            chrome.resize(width: newSize.width)
        }
        .gesture(
            SpatialTapGesture()
                .onEnded({ value in
                    Task { @MainActor in
                        let x = value.location.x
                        let y = value.location.y
                        if y < chrome.bottom {
                            app.activeTab?.blur()
                            chrome.click(x: x, y: y)
                            app.objectWillChange.send()
                        } else {
                            chrome.blur()
                            app.activeTab?.click(x: x, y: y - chrome.bottom)
                        }
                    }
                })
        )
        .task {
            app.displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
            chrome.tabManager = app
            chrome.bookmarks = bookmarks
            chrome.resize(width: app.windowSize.width)
            app.topInset = chrome.bottom
            Tab.pageSource = { scheme, path in
                guard scheme == "about", path == "bookmarks" else { return nil }
                let items = await MainActor.run {
                    bookmarks.urls.map { url in
                    " <li><a href=\"\(url)\">\(url)</a></li>"
                    }.joined(separator: "\n")
                }
                return(
                    200, [:],
                    """
                    <html><body>
                    <h1>Bookmarks</h1>
                    <ul>\n\(items)\n</ul>
                    </body></html>
                    """
                )
            }
            app.newTab(WebURL("https://browser.engineering"))
        }
    }
}
