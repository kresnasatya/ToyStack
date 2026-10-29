import CoreGraphics
import Foundation

private struct FrameState {
    let url: WebURL
    let payload: String?
}

private struct HistoryEntry {
    let state: FrameState
    let windowID: Int
    let from: FrameState?
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
    var hasVisitedURLs: Bool { !visitedURL.isEmpty }
    private var history: [HistoryEntry] = []
    private var historyIndex: Int = -1

    private var nextWindowID: Int = 0
    var windowIDToFrame: [Int: Frame] = [:]
    private(set) var rootFrame: Frame!
    private(set) var focusedFrame: Frame!

    public private(set) var tabHeight: CGFloat
    public private(set) var tabWidth: CGFloat

    var pageZoom: CGFloat { rootFrame.pageZoom }

    public var canGoBack: Bool { nearestLiveIndex(from: historyIndex - 1, direction: -1) != nil }
    public var canGoForward: Bool { nearestLiveIndex(from: historyIndex + 1, direction: 1) != nil }

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
    public var isLoaded: Bool { rootFrame.loaded }
    var focus: Element? { focusedFrame.focus }
    private(set) var accessibilityTree: AccessibilityNode? = nil
    var needsAccessibility: Bool = false
    public var hasScrollElement: Bool { focusedFrame.hasScrollElement }

    init(tabHeight: CGFloat, tabWidth: CGFloat) {
        self.tabHeight = tabHeight
        self.tabWidth = tabWidth
        let frame: Frame = Frame(
            tab: self,
            parent: nil,
            frameWidth: tabWidth,
            frameHeight: tabHeight
        )
        rootFrame = frame
        focusedFrame = frame
    }

    func markVisited(_ url: String) {
        visitedURL.insert(url)
    }

    func hasVisited(_ url: String) -> Bool {
        visitedURL.contains(url)
    }

    func reserveWindowID() -> Int {
        let id: Int = nextWindowID
        nextWindowID += 1
        return id
    }

    public func load(_ url: WebURL, payload: String? = nil) {
        load(url, payload: payload, in: rootFrame)
    }

    func load(_ url: WebURL, payload: String? = nil, in frame: Frame) {
        recordNavigation(url: url, payload: payload, frame: frame)
        frame.load(url, payload: payload)
    }

    private func recordNavigation(url: WebURL, payload: String?, frame: Frame) {
        let prior: HistoryEntry? = history.prefix(historyIndex + 1).last(where: { $0.windowID == frame.windowID })
        let currentURL: WebURL? = frame.url
        let from: FrameState? = prior?.state ?? currentURL.map({ FrameState(url: $0, payload: nil) })
        history = Array(history.prefix(historyIndex + 1))
        history.append(
            HistoryEntry(
                state: FrameState(url: url, payload: payload),
                windowID: frame.windowID,
                from: from
            )
        )
        historyIndex = history.count - 1
        browser?.navigationStateChanged()
    }

    func isSameDocument(_ a: WebURL, _ b: WebURL) -> Bool {
        return a.scheme == b.scheme
            && a.host == b.host
            && a.port == b.port
            && a.path == b.path
    }

    func navigateToFragment(_ resolved: WebURL, in frame: Frame) {
        recordNavigation(url: resolved, payload: nil, frame: frame)
        frame.url = resolved
        frame.jumpTo(resolved.fragment)
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
        browser?.beginFrame()
        let frames: [Frame] = windowIDToFrame.values.sorted(by: { $0.windowID < $1.windowID })
        for frame in frames where frame.loaded {
            frame.runAnimationFrame()
        }
        if needsAccessibility, browser?.accessibilityIsOn == true {
            browser?.measure.start("BrowserTab.a11y")
            let tree: AccessibilityNode = AccessibilityNode(node: rootFrame.nodes)
            tree.build()
            accessibilityTree = tree
            browser?.measure.stop("BrowserTab.a11y")
            needsAccessibility = false
        }
        rootFrame.paint()
        for frame in frames {
            frame.needsPaint = false
        }
        rootFrame.commitFrame()
    }

    public func linkURL(at x: CGFloat, y: CGFloat) -> WebURL? {
        let zoom: CGFloat = rootFrame.pageZoom
        return rootFrame.linkURL(at: x / zoom, y: y / zoom)
    }

    public func scrollbarCommands() -> [any DisplayCommand] {
        rootFrame.scrollbarCommands()
    }

    public func resize(width: CGFloat, height: CGFloat) {
        let widthChanged: Bool = width != tabWidth
        let heightChanged: Bool = height != tabHeight
        guard widthChanged || heightChanged else { return }
        tabWidth = width
        tabHeight = height
        browser?.measure.counter(
            "BrowserTab.resize",
            [
                "width": Int(width),
                "height": Int(height),
                "widthChanged": widthChanged ? 1 : 0,
                "heightChanged": heightChanged ? 1 : 0,
            ]
        )
        rootFrame.frameWidth = width / rootFrame.pageZoom
        rootFrame.frameHeight = height / rootFrame.pageZoom
        rootFrame.setNeedsViewportResize()
    }

    public func scrollDown() {
        focusedFrame.scrollDown()
    }

    public func scrollUp() {
        focusedFrame.scrollUp()
    }

    public func scrollAt(x: CGFloat, y: CGFloat, deltaY: CGFloat) {
        browser?.measure.span("BrowserTab.scrollAt", category: .input) {
            let zoom: CGFloat = rootFrame.pageZoom
            rootFrame.scrollAt(x: x / zoom, y: y / zoom, deltaY: deltaY / zoom)
        }
    }

    public func scrollBy(deltaY: CGFloat) {
        browser?.measure.span("BrowserTab.scrollBy", category: .input) {
            rootFrame.scrollBy(deltaY: deltaY / rootFrame.pageZoom)
        }
    }

    public func scrollElementDown() {
        focusedFrame.scrollElementDown()
    }

    public func scrollElementUp() {
        focusedFrame.scrollElementUp()
    }

    public func goBack() {
        guard let target: Int = nearestLiveIndex(from: historyIndex - 1, direction: -1) else { return }
        rewindFrames(after: target)
        historyIndex = target
        browser?.navigationStateChanged()
    }

    public func goForward() {
        guard let target: Int = nearestLiveIndex(from: historyIndex + 1, direction: 1) else { return }
        replayFrames(from: historyIndex + 1, through: target)
        historyIndex = target
        browser?.navigationStateChanged()
    }

    private func rewindFrames(after index: Int) {
        var handled: Set<Int> = []
        for i in (index + 1)..<history.count {
            let windowID: Int = history[i].windowID
            guard handled.insert(windowID).inserted else { continue }
            guard let frame = windowIDToFrame[windowID], let from = history[i].from else { continue }
            if from.payload != nil,
                !BrowserTab.showConfirm("Resubmit form?", "This page was loaded by submitting a form. Do you want to resubmit it?") {
                continue
            }
            enter(frame, state: from)
        }
    }

    private func replayFrames(from start: Int, through end: Int) {
        var handled: Set<Int> = []
        for i in stride(from: end, through: start, by: -1) {
            let windowID: Int = history[i].windowID
            guard handled.insert(windowID).inserted else { continue }
            guard let frame = windowIDToFrame[windowID] else { continue }
            enter(frame, state: history[i].state)
        }
    }

    private func nearestLiveIndex(from index: Int, direction: Int) -> Int? {
        var i: Int = index
        while i >= 0 && i < history.count {
            if windowIDToFrame[history[i].windowID] != nil { return i }
            i += direction
        }
        return nil
    }

    private func enter(_ frame: Frame, state: FrameState) {
        if let payload = state.payload {
            frame.load(state.url, payload: payload)
        } else if let currentURL = frame.url, isSameDocument(currentURL, state.url) {
            frame.url = state.url
            frame.jumpTo(state.url.fragment)
        } else {
            frame.load(state.url)
        }
    }

    public func keypress(_ char: String) {
        focusedFrame.keypress(char)
    }

    public func blur() {
        focusedFrame.blur()
    }

    func focusElement(_ node: Element?, showRing: Bool = true) {
        focusedFrame.focusElement(node, showRing: showRing)
    }

    func setFocusedFrame(_ frame: Frame) {
        guard focusedFrame !== frame else { return }
        let previous: Frame? = focusedFrame
        focusedFrame = frame
        previous?.clearFocus()
    }

    func postMessage(message: String, targetWindowID: Int, targetOrigin: String) {
        guard let target = windowIDToFrame[targetWindowID] else { return }
        guard matchesTargetOrigin(targetOrigin, frame: target) else { return }
        target.js.dispatchPostMessage(message: message)
    }

    private func matchesTargetOrigin(_ targetOrigin: String, frame: Frame) -> Bool {
        guard targetOrigin != "*" else { return true }
        guard let targetURL = frame.url else { return false }
        return WebURL(targetOrigin).origin() == targetURL.origin()
    }

    @discardableResult
    public func advanceTab() -> Bool {
        let targets: [FocusTarget] = focusOder(of: rootFrame)
        var start: Int = 0
        if let focused = focusedFrame.focus,
            let idx = targets.firstIndex(where: { $0.frame === focusedFrame && $0.element === focused }) {
            start = idx + 1
        } else if let idx = targets.firstIndex(where: { $0.frame === focusedFrame }) {
            start = idx
        }
        guard start < targets.count else {
            focusedFrame.focusElement(nil)
            return false
        }
        let target: FocusTarget = targets[start]
        target.frame.focusElement(target.element)
        return true
    }

    public func click(x: CGFloat, y: CGFloat) {
        let zoom: CGFloat = rootFrame.pageZoom
        rootFrame.click(x: x / zoom, y: y / zoom)
    }

    public func enterKey() {
        focusedFrame.enterKey()
    }

    func zoomBy(_ increment: Bool) {
        rootFrame.zoomBy(increment)
    }

    func resetZoom() {
        rootFrame.resetZoom()
    }

    public func setZoom(_ newZoom: CGFloat) {
        rootFrame.setZoom(newZoom)
    }
}
