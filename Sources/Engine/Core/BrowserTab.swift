import CoreGraphics
import Foundation

private struct HistoryEntry {
    let url: WebURL
    let payload: String?
}

@MainActor
public class BrowserTab {
    public nonisolated(unsafe) static var showAlert: (String, String) -> Void = { title, message in
        print("[alert] \(title): \(message)")
    }
    public nonisolated(unsafe) static var showConfirm: (String, String) -> Bool = { title, message in
        print("[confirm] \(title): \(message)")
        return true
    }
    public nonisolated(unsafe) static var pageSource: ((_ scheme: String, _ path: String) async -> (
        status: Int, headers: [String: String], content: String
    )?)? = nil

    private nonisolated(unsafe) var visitedURL: Set<String> = []
    private var history: [HistoryEntry] = []
    private var historyIndex: Int = -1

    private var nextWindowID: Int = 0
    var windowIDToFrame: [Int: Frame] = [:]
    private(set) var rootFrame: Frame!

    public private(set) var tabHeight: CGFloat
    private var tabWidth: CGFloat

    public var canGoBack: Bool { historyIndex > 0 }
    public var canGoForward: Bool { historyIndex < history.count - 1 }

    private(set) var taskRunner: TaskRunner = TaskRunner()
    var networkTaskRunner: NetworkTaskRunner?
    weak var browser: Browser?

    var prefersDark: Bool = false {
        didSet {
            if oldValue != prefersDark { rootFrame?.setNeedsRender() }
        }
    }

    var forcedColors: Bool = false {
        didSet {
            if oldValue != forcedColors { rootFrame?.setNeedsRender() }
        }
    }

    public var url: WebURL! { rootFrame.url }
    var nodes: any DOMNode { rootFrame.nodes }
    var document: DocumentLayout? { rootFrame.document }
    var displayList: [any DisplayItem] { rootFrame.displayList }
    public var title: String { rootFrame.title }
    public var isSecure: Bool { rootFrame.isSecure }
    var focus: Element? { rootFrame.focus }
    var accessibilityTree: AccessibilityNode? { rootFrame.accessibilityTree }
    public var hasScrollElement: Bool { rootFrame.hasScrollElement }

    init(tabHeight: CGFloat, tabWidth: CGFloat) {
        self.tabHeight = tabHeight
        self.tabWidth = tabWidth
        let frame: Frame = Frame(
            windowID: 0,
            tab: self,
            frameWidth: tabWidth,
            frameHeight: tabHeight
        )
        rootFrame = frame
        windowIDToFrame[0] = frame
        nextWindowID = 1
    }

    func markVisited(_ url: String) {
        visitedURL.insert(url)
    }

    func hasVisited(_ url: String) -> Bool {
        visitedURL.contains(url)
    }

    public func load(_ url: WebURL, payload: String? = nil) {
        history = Array(history.prefix(historyIndex + 1))
        history.append(HistoryEntry(url: url, payload: payload))
        historyIndex = history.count - 1
        rootFrame.load(url, payload: payload)
    }

    private func isSameDocument(_ a: WebURL, _ b: WebURL) -> Bool {
        return a.scheme == b.scheme
            && a.host == b.host
            && a.port == b.port
            && a.path == b.path
    }

    func navigateToFragment(_ resolved: WebURL) {
        history = Array(history.prefix(historyIndex + 1))
        history.append(HistoryEntry(url: resolved, payload: nil))
        historyIndex = history.count - 1
        rootFrame.url = resolved
        rootFrame.jumpTo(resolved.fragment)
    }

    nonisolated static func isExecutableScript(
        status: Int,
        headers: [String: String],
        url: WebURL
    ) -> Bool {
        guard status == 200 else {
            print("Refused execute script from", url.toString(), "- server replied", status)
            return false
        }
        guard let contentType = headers["content-type"] else { return true }
        guard MIMEType.isJavaScript(contentType) else {
            print(
                "Refused to execute script from", url.toString(),
                "because it's MIME type (\(MIMEType.essence(contentType))) is not executable"
            )
            return false
        }
        return true
    }

    nonisolated static func isUsableStylesheet(
        status: Int,
        headers: [String: String],
        url: WebURL
    ) -> Bool {
        guard status == 200 else {
            print("Refused to apply stylesheet from", url.toString(), "- server replied", status)
            return false
        }
        guard let contentType = headers["content-type"] else { return true }
        guard MIMEType.isCSS(contentType) else {
            print(
                "Refused to apply stylesheet from", url.toString(),
                "because it's MIME type (\(MIMEType.essence(contentType))) is not text/css"
            )
            return false
        }
        return true
    }

    func runAnimationFrame() {
        rootFrame.runAnimationFrame()
    }

    public func linkURL(at x: CGFloat, y: CGFloat) -> WebURL? {
        rootFrame.linkURL(at: x, y: y)
    }

    public func scrollbarCommands() -> [any DisplayCommand] {
        rootFrame.scrollbarCommands()
    }

    public func resize(width: CGFloat, height: CGFloat) {
        tabWidth = width
        tabHeight = height
        rootFrame.frameWidth = width
        rootFrame.frameHeight = height
        rootFrame.setNeedsRender()
    }

    public func scrollDown() {
        rootFrame.scrollDown()
    }

    public func scrollUp() {
        rootFrame.scrollUp()
    }

    public func scrollAt(x: CGFloat, y: CGFloat, deltaY: CGFloat) {
        rootFrame.scrollAt(x: x, y: y, deltaY: deltaY)
    }

    public func scrollBy(deltaY: CGFloat) {
        rootFrame.scrollBy(deltaY: deltaY)
    }

    public func scrollElementDown() {
        rootFrame.scrollElementDown()
    }

    public func scrollElementUp() {
        rootFrame.scrollElementUp()
    }

    public func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        let entry: HistoryEntry = history[historyIndex]
        if let payload = entry.payload {
            if BrowserTab.showConfirm("Resubmit form?", "This page was loaded by submitting a form. Do you want to resubmit it?") {
                rootFrame.load(entry.url, payload: payload)
            } else {
                historyIndex += 1
            }
        } else if let currentURL = rootFrame.url, isSameDocument(currentURL, entry.url) {
            rootFrame.url = entry.url
            rootFrame.jumpTo(entry.url.fragment)
        } else {
            rootFrame.load(entry.url)
        }
    }

    public func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        let entry: HistoryEntry = history[historyIndex]
        if let currentURL = rootFrame.url, isSameDocument(currentURL, entry.url) {
            rootFrame.url = entry.url
            rootFrame.jumpTo(entry.url.fragment)
        } else {
            rootFrame.load(entry.url, payload: entry.payload)
        }
    }

    public func keypress(_ char: String) {
        rootFrame.keypress(char)
    }

    public func blur() {
        rootFrame.blur()
    }

    func focusElement(_ node: Element?, showRing: Bool = true) {
        rootFrame.focusElement(node, showRing: showRing)
    }

    @discardableResult
    public func advanceTab() -> Bool {
        rootFrame.advanceTab()
    }

    public func click(x: CGFloat, y: CGFloat) {
        rootFrame.click(x: x, y: y)
    }

    public func enterKey() {
        rootFrame.enterKey()
    }

    func zoomBy(_ increment: Bool) {
        rootFrame.zoomBy(increment)
    }

    func resetZoom() {
        rootFrame.resetZoom()
    }
}
