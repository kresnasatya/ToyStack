import Engine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        BrowserTab.showAlert = { title, message in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        BrowserTab.showConfirm = { title, message in
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

public struct BrowserView: View {
    @StateObject private var app = Browser()
    @State private var addressFocus: AddressFocus = AddressFocus()
    @Environment(\.openWindow) private var openWindow
    @State private var browserWindow: NSWindow?
    let bookmarks: Bookmarks

    init(bookmarks: Bookmarks) {
        self.bookmarks = bookmarks
    }

    public var body: some View {
        ChromeView(browser: app, bookmarks: bookmarks, addressFocus: addressFocus) {
            BrowserContentView(browser: app)
                .background(app.commitedForcedColors ? Color(engine: BrowserColor(cssName: ForcedColor.canvas)) : (app.commitedPrefersDark ? Color.black : Color.white))
                .contentShape(Rectangle())
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { newSize in
                    app.resize(to: newSize, deferLayout: true)
                }
                .gesture(
                    SpatialTapGesture()
                        .onEnded({ value in
                            Task { @MainActor in
                                addressFocus.blur()
                                app.activeTab?.click(x: value.location.x, y: value.location.y)
                            }
                        })
                )
        }
        .background(
            WindowReader { window in
                browserWindow = window
                window.styleMask.insert(.resizable)
                window.contentMinSize = NSSize(width: 320, height: 240)
            }
        )
        .onAppear {
            NSEvent.addLocalMonitorForEvents(
                matching: .keyDown,
                handler: { [weak app, addressFocus] event in
                    guard event.window === browserWindow else { return event }
                    guard let app else { return event }
                    let flags: NSEvent.ModifierFlags = event.modifierFlags
                    let isBrowserShortcut: Bool =
                        flags.contains(.control)
                        || (flags.contains(.command) && event.keyCode == KeyCode.n)
                        || event.keyCode == KeyCode.tab
                    let isEditingText: Bool = event.window?.firstResponder is NSTextView
                    if isEditingText && !isBrowserShortcut {
                        return event
                    }
                    Task { @MainActor in
                        if flags.contains(.command) && event.keyCode == KeyCode.n {
                            openWindow(id: "browser", value: UUID())
                        } else if flags.contains(.command) && event.keyCode == KeyCode.leftArrow {
                            app.activeTab?.goBack()
                        } else if event.keyCode == KeyCode.downArrow {
                            if let tab = app.activeTab, tab.hasScrollElement {
                                tab.scrollElementDown()
                            } else {
                                app.activeTab?.scrollDown()
                            }
                        } else if event.keyCode == KeyCode.upArrow {
                            if let tab = app.activeTab, tab.hasScrollElement {
                                tab.scrollElementUp()
                            } else {
                                app.activeTab?.scrollUp()
                            }
                        } else if event.keyCode == KeyCode.returnKey {
                            app.activeTab?.enterKey()
                        } else if event.keyCode == KeyCode.tab {
                            if flags.contains(.control) {
                                app.cycleTabs()
                            } else if isEditingText {
                                addressFocus.blur()
                                _ = app.activeTab?.advanceTab()
                            } else if !(app.activeTab?.advanceTab() ?? false) {
                                addressFocus.focus()
                            }
                        } else if flags.contains(.control) {
                            switch event.keyCode {
                            case KeyCode.a:
                                app.toggleAccessibility()
                            case KeyCode.s:
                                app.advanceAccessibility()
                            case KeyCode.d:
                                app.togglePrefersDark()
                            case KeyCode.h:
                                app.toggleForcedColors()
                            case KeyCode.q:
                                NSApplication.shared.terminate(nil)
                            case KeyCode.t:
                                app.newTab(WebURL("about:blank"))
                            case KeyCode.equal:
                                app.incrementZoom(true)
                            case KeyCode.minus:
                                app.incrementZoom(false)
                            case KeyCode.zero:
                                app.resetZoom()
                            case KeyCode.l:
                                addressFocus.focus()
                            default:
                                break
                            }
                        } else if let char = event.characters, !char.isEmpty {
                            let scalar = char.unicodeScalars.first!.value
                            if scalar >= 0x20 && scalar < 0x7F {
                                app.activeTab?.keypress(char)
                            }
                        }
                    }
                    return nil
                }
            )
            NSEvent.addLocalMonitorForEvents(
                matching: .scrollWheel,
                handler: { [weak app] event in
                    guard event.window === browserWindow else { return event }
                    guard let app else { return event }
                    Task { @MainActor in
                        guard event.scrollingDeltaY != 0 else { return }
                        let deltaY = event.hasPreciseScrollingDeltas
                            ? event.scrollingDeltaY
                            : event.scrollingDeltaY * 18
                        let loc = event.locationInWindow
                        let y: CGFloat = app.windowSize.height - loc.y
                        if y > 0 {
                            app.activeTab?.scrollAt(x: loc.x, y: y, deltaY: deltaY)
                        } else {
                            app.activeTab?.scrollBy(deltaY: deltaY)
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
                        let y: CGFloat = app.windowSize.height - loc.y
                        guard y >= 0 else { return }
                        if let linkURL = app.activeTab?.linkURL(at: loc.x, y: y) {
                            app.newTab(linkURL)
                        }
                    }
                    return nil
                }
            )
            NSEvent.addLocalMonitorForEvents(
                matching: .mouseMoved,
                handler: { [weak app] event in
                    guard event.window === browserWindow else { return event }
                    guard let app else { return event }
                    Task { @MainActor in
                        let loc = event.locationInWindow
                        let y: CGFloat = app.windowSize.height - loc.y
                        guard y >= 0 else {
                            app.activeTab?.clearHover()
                            return
                        }
                        app.handleHover(x: loc.x, y: y)
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
        .task {
            app.usesAsyncLayout = true
            app.displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
            if let space: CGColorSpace = NSScreen.main?.colorSpace?.cgColorSpace {
                app.displayColorSpace = space
            }
            BrowserTab.pageSource = { scheme, path in
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
