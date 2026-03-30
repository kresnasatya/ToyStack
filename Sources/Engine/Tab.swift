import AppKit
import Foundation

private struct HistoryEntry {
    let url: WebURL
    let payload: String?  // nil = GET, non-nil = POST
}

@MainActor
public class Tab {
    private(set) var url: WebURL!
    private(set) var nodes: any DOMNode = Element(tag: "html", attributes: [:], parent: nil)
    private(set) var document: DocumentLayout?
    private(set) var displayList: [Any] = []
    public private(set) var title: String = "New Tab"
    private(set) var isSecure: Bool = false

    private var scroll: CGFloat = 0
    private var tabHeight: CGFloat
    private var tabWidth: CGFloat
    private var history: [HistoryEntry] = []
    private var historyIndex: Int = -1
    private var focus: Element?
    private var allowedOrigins: [String]?
    private var rules: [(String?, any CSSSelector, [String: String])] = []
    private var js: JSRuntime!
    private var loadedScriptURLs: Set<String> = []
    private var referrerPolicy: String = ""

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    private(set) var taskRunner: TaskRunner = TaskRunner()
    private(set) var accessibilityTree: AccessibilityNode? = nil
    private var compositedUpdates: [ObjectIdentifier: VisualEffect] = [:]

    private var needsRender: Bool = false
    private var needsStyle: Bool = false
    private var needsLayout: Bool = false
    private var needsAccessibility: Bool = false
    private var needsPaint: Bool = false

    private(set) var darkMode: Bool = false

    weak var browser: Browser?

    init(tabHeight: CGFloat, tabWidth: CGFloat) {
        self.tabHeight = tabHeight
        self.tabWidth = tabWidth
    }

    func load(_ url: WebURL, payload: String? = nil) async {
        // Truncate any forward history beyond the current position
        // then record this new URL as the current entry.
        history = Array(history.prefix(historyIndex + 1))
        history.append(HistoryEntry(url: url, payload: payload))
        historyIndex = history.count - 1
        await performLoad(url, payload: payload)
    }

    private func performLoad(_ url: WebURL, payload: String? = nil) async {
        let headers: [String: String]
        let body: String
        let certErrorCodes: [URLError.Code] = [
            .serverCertificateUntrusted,
            .serverCertificateHasBadDate,
            .serverCertificateNotYetValid,
            .serverCertificateHasUnknownRoot,
        ]

        do {
            (headers, body) = try await url.request(
                referrer: effectiveReferrer(for: url), payload: payload)
        } catch let error as URLError where certErrorCodes.contains(error.code) {
            let alert = NSAlert()
            alert.messageText = "Certificate Error"
            alert.informativeText =
                "The certificate for \(url.host) is invalid. Your connection may not be private."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        } catch {
            return
        }
        isSecure = url.scheme == "https"

        scroll = 0
        self.url = url
        visitedURL.insert(url.toString())
        nodes = HTMLParser(body: body).parse()

        for node in treeToList(nodes) {
            if let el = node as? Element, el.tag == "input", el.attributes["type"] == "checkbox" {
                el.isChecked = el.attributes["checked"] != nil
            }
        }

        js = JSRuntime(tab: self)

        // Extract the title
        let titleText =
            treeToList(nodes)
            .compactMap({ $0 as? Element })
            .first(where: { $0.tag == "title" })?.children
            .compactMap({ $0 as? TextNode })
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = titleText.isEmpty ? url.toString() : titleText

        // Parse Content-Security-Policy header
        allowedOrigins = nil
        referrerPolicy = headers["referrer-policy"] ?? ""
        if let csp = headers["content-security-policy"] {
            let parts = csp.split(separator: " ").map(String.init)
            if parts.first == "default-src" {
                allowedOrigins = parts.dropFirst().map { WebURL($0).origin() }
            }
        }

        // Collect linked stylesheets and extend the default rules
        rules = defaultStyleSheet
        let linkNodes = treeToList(nodes)
            .compactMap {
                $0 as? Element
            }
            .filter {
                $0.tag == "link"
                    && $0.attributes["rel"] == "stylesheet"
                    && $0.attributes["href"] != nil
            }

        for link in linkNodes {
            let styleURL = url.resolve(link.attributes["href"]!)
            guard allowedRequest(styleURL) else {
                print("Blocked style", link.attributes["href"]!, "due to CSP")
                continue
            }
            guard
                let (_, styleBody) = try? await styleURL.request(
                    referrer: effectiveReferrer(for: styleURL))
            else { continue }
            rules.append(contentsOf: CSSParser(styleBody).parse())
        }

        // Collect inline <style> sheets and append their rules
        let styleNodes = treeToList(nodes)
            .compactMap({ $0 as? Element })
            .filter({ $0.tag == "style" })

        for styleNode in styleNodes {
            let css = styleNode.children
                .compactMap({ $0 as? TextNode })
                .map({ $0.text })
                .joined()
            rules.append(contentsOf: CSSParser(css).parse())
        }

        // Load and execute linked scripts
        let scriptNodes = treeToList(nodes)
            .compactMap { $0 as? Element }
            .filter { $0.tag == "script" && $0.attributes["src"] != nil }

        for scriptNode in scriptNodes {
            let scriptURL = url.resolve(scriptNode.attributes["src"]!)
            guard allowedRequest(scriptURL) else {
                print("Blocked script", scriptNode.attributes["src"]!, "due to CSP")
                continue
            }
            guard
                let (_, scriptBody) = try? await scriptURL.request(
                    referrer: effectiveReferrer(for: scriptURL))
            else {
                continue
            }
            js.run(script: scriptURL.toString(), code: scriptBody)
            loadedScriptURLs.insert(scriptURL.toString())
        }

        js.defineIDs()

        setNeedsRender()

        if let fragment = url.fragment {
            scrollToFragment(fragment)
        }
    }

    private func effectiveReferrer(for targetURL: WebURL) -> WebURL? {
        switch referrerPolicy {
        case "no-referrer":
            return nil
        case "same-origin":
            return url?.origin() == targetURL.origin() ? url : nil
        default:
            return url  // no policy: always send referrer
        }
    }

    func allowedRequest(_ url: WebURL) -> Bool {
        allowedOrigins == nil || (allowedOrigins?.contains(url.origin()) ?? false)
    }

    func runNewScripts(in root: any DOMNode) {
        for node in treeToList(root) {
            guard let el = node as? Element, el.tag == "script",
                let src = el.attributes["src"]
            else { continue }
            let scriptURL = url.resolve(src)
            guard allowedRequest(scriptURL) else {
                print("Blocked script", src, "due to CSP")
                continue
            }
            let urlStr = scriptURL.toString()
            guard !loadedScriptURLs.contains(urlStr) else { continue }
            guard let (_, body) = scriptURL.requestSync() else { continue }
            loadedScriptURLs.insert(urlStr)
            js.run(script: urlStr, code: body)
        }
    }

    func reloadStylesheets() {
        rules = defaultStyleSheet
        for node in treeToList(nodes) {
            guard let el = node as? Element else { continue }
            if el.tag == "link", el.attributes["rel"] == "stylesheet",
                let href = el.attributes["href"]
            {
                let styleURL = url.resolve(href)
                guard allowedRequest(styleURL) else { continue }
                guard let (_, body) = styleURL.requestSync() else { continue }
                rules.append(contentsOf: CSSParser(body).parse())
            }
            if el.tag == "style" {
                let css = el.children.compactMap({ $0 as? TextNode }).map(\.text).joined()
                rules.append(contentsOf: CSSParser(css).parse())
            }
        }
    }

    func render() {
        if needsStyle {
            let sortedRules = rules.sorted(by: { cascadePriority($0) < cascadePriority($1) })
            precomputeHas(node: nodes, rules: sortedRules)

            // Save old styles before applying new ones, for animation detection
            var oldStyles: [ObjectIdentifier: [String: String]] = [:]
            for node in treeToList(nodes) {
                oldStyles[ObjectIdentifier(node)] = node.style
            }

            inheritedProperties["color"] = darkMode ? "white" : "black"
            applyStyle(node: nodes, rules: sortedRules, darkMode: darkMode)

            // Detect style changes and create animations
            for node in treeToList(nodes) {
                let old = oldStyles[ObjectIdentifier(node)] ?? [:]
                let newAnimations = diffStyles(node: node, oldStyle: old, newStyle: node.style)
                for (property, animation) in newAnimations {
                    node.animations[property] = animation
                }
            }

            // Override color for visited links
            for node in treeToList(nodes) {
                guard let el = node as? Element, el.tag == "a",
                    let href = el.attributes["href"]
                else {
                    continue
                }
                if visitedURL.contains(url.resolve(href).toString()) {
                    el.style["color"] = "purple"
                }
            }

            needsStyle = false
            needsLayout = true
        }

        if needsLayout {
            let doc = DocumentLayout(node: nodes)
            doc.layout(availableWidth: tabWidth)
            document = doc

            needsLayout = false
            needsAccessibility = true
            needsPaint = true
        }

        if needsAccessibility {
            // Build accessibility tree
            let a11yTree = AccessibilityNode(node: nodes)
            a11yTree.build()
            accessibilityTree = a11yTree

            needsAccessibility = false
        }

        if needsPaint {
            guard let doc = document else { return }
            var list: [Any] = []
            paintTree(doc, into: &list)
            displayList = list
            needsPaint = false
        }

        browser?.setNeedsAnimationFrame(self)
    }

    func runAnimationFrame() {
        js.run(script: "raf", code: "__runRAFHandlers()")
        let needsComposite = needsStyle || needsLayout
        var needsPaint = false
        for node in treeToList(nodes) {
            for (property, animation) in node.animations {
                if let value = animation.animate() {
                    if property == "transform-x" || property == "transform-y" {
                        node.style[property] = value
                        if let x = node.style["transform-x"],
                            let y = node.style["transform-y"]
                        {
                            node.style["transform"] = "translate(\(x)px, \(y)px)"
                        }
                    } else {
                        node.style[property] = value
                    }
                    compositedUpdates[ObjectIdentifier(node)] =
                        node.layoutObject as? Engine.VisualEffect
                    needsPaint = true
                } else {
                    node.animations.removeValue(forKey: property)
                }
            }
        }

        if needsPaint {
            setNeedsPaint()
        }

        if needsRender {
            needsRender = false
            render()
        }

        let docHeight = document.map({ $0.height + 2 * VSTEP }) ?? 0

        // nil signals Browser to do a full composite
        // dict signals Browser to only update specific layers
        let updates: [ObjectIdentifier: VisualEffect]? = needsComposite ? nil : compositedUpdates
        let data = CommitData(
            url: url!, scroll: scroll, height: docHeight, displayList: displayList,
            compositedUpdates: updates, accessibilityTree: accessibilityTree, focus: focus
        )
        compositedUpdates = [:]
        browser?.commit(tab: self, data: data)
    }

    private func scrollToFragment(_ id: String) {
        guard let doc = document else { return }
        let target = treeToList(doc).first(where: {
            ($0.node as? Element)?.attributes["id"] == id
        })
        if let target = target {
            scroll = target.y
        }
    }

    public func linkURL(at x: CGFloat, y: CGFloat) -> WebURL? {
        let adjustedY = y + scroll
        guard let doc = document else { return nil }
        let objs = treeToList(doc).filter {
            $0.x <= x && x < $0.x + $0.width
                && $0.y <= adjustedY && adjustedY < $0.y + $0.height
        }
        guard let hit = objs.last else { return nil }
        var elt: (any DOMNode)? = hit.node
        while let node = elt {
            if let el = node as? Element, el.tag == "a", let href = el.attributes["href"] {
                return url?.resolve(href)
            }
            elt = node.parent
        }
        return nil
    }

    public func visibleCommands(offset: CGFloat) -> [(command: Any, scroll: CGFloat)] {
        displayList.compactMap({ item in
            let rect: Rect?
            if let cmd = item as? any PaintCommand {
                rect = cmd.rect
            } else if let ve = item as? VisualEffect {
                rect = ve.rect
            } else {
                rect = nil
            }
            guard let r = rect, r.top <= scroll + tabHeight, r.bottom >= scroll else { return nil }
            return (item, scroll)
        })
    }

    public func scrollbarCommands() -> [Any] {
        guard let doc = document else { return [] }
        let docHeight = doc.height
        guard docHeight > tabHeight else { return [] }

        let scrollbarWidth: CGFloat = 8
        let barHeight = (tabHeight / docHeight) * tabHeight
        let barTop = (scroll / docHeight) * tabHeight

        let barRect = Rect(
            left: tabWidth - scrollbarWidth, top: barTop, right: tabWidth,
            bottom: barTop + barHeight)

        return [DrawRect(rect: barRect, color: "blue")]
    }

    public func resize(width: CGFloat, height: CGFloat) {
        tabWidth = width
        tabHeight = height

        setNeedsRender()
    }

    public func scrollDown() {
        let maxY = max((document?.height ?? 0) + 2 * VSTEP - tabHeight, 0)
        scroll = min(scroll + SCROLL_STEP, maxY)
        browser?.applyScroll(scroll)
    }

    public func scrollUp() {
        scroll = max(scroll - SCROLL_STEP, 0)
        browser?.applyScroll(scroll)
    }

    func goBack() async {
        guard canGoBack else { return }
        historyIndex -= 1
        let entry = history[historyIndex]
        if let payload = entry.payload {
            let alert = NSAlert()
            alert.messageText = "Resubmit form?"
            alert.informativeText =
                "This page was loaded by submitting a form. Do you want to resubmit it?"
            alert.addButton(withTitle: "Resubmit")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                await performLoad(entry.url, payload: payload)
            } else {
                historyIndex += 1  // user said no - undo the index change
            }
        } else {
            await performLoad(entry.url)
        }
    }

    func goForward() async {
        guard canGoForward else { return }
        historyIndex += 1
        let entry = history[historyIndex]
        await performLoad(entry.url, payload: entry.payload)
    }

    public func keypress(_ char: String) {
        guard let f = focus else { return }
        if js.dispatchEvent(type: "keydown", elt: f) { return }
        f.attributes["value", default: ""] += char

        setNeedsRender()
    }

    public func blur() {
        focus?.isFocused = false
        focus = nil

        setNeedsRender()
    }

    private func sourceOf(_ cmd: any PaintCommand) -> (any LayoutObject)? {
        if let c = cmd as? DrawRect, let s = c.source { return s }
        if let c = cmd as? DrawText, let s = c.source { return s }
        if let c = cmd as? DrawLine, let s = c.source { return s }
        return nil
    }

    public func click(x: CGFloat, y: CGFloat) async {
        focus?.isFocused = false
        focus = nil

        let adjustedY = y + scroll
        let paintHits = displayList.compactMap({ $0 as? any PaintCommand })
        let hits = paintHits.filter({
            $0.rect.left <= x && x < $0.rect.right
                && $0.rect.top <= adjustedY && adjustedY < $0.rect.bottom
        })
        guard
            let source = hits.last(where: { sourceOf($0) != nil }).flatMap({
                sourceOf($0)
            })
        else {
            setNeedsRender()
            return
        }

        // Dispatch once on the innermost element - JS bubbles it up the tree
        let prevented = js.dispatchEvent(type: "click", elt: source.node)

        if !prevented {
            var elt: (any DOMNode)? = source.node
            while let node = elt {
                if node is TextNode {
                    // fall through to parent
                } else if let el = node as? Element, el.tag == "a", let href = el.attributes["href"]
                {
                    if href.hasPrefix("#") {
                        let resolved = url.resolve(href)
                        // Push to history without reolading the page
                        history = Array(history.prefix(historyIndex + 1))
                        history.append(HistoryEntry(url: resolved, payload: nil))
                        historyIndex = history.count - 1
                        self.url = resolved
                        scrollToFragment(String(href.dropFirst()))
                        browser?.applyScroll(scroll)
                    } else {
                        await load(url.resolve(href))
                    }
                    return
                } else if let el = node as? Element, el.tag == "input" {
                    if el.attributes["type"] == "checkbox" {
                        el.isChecked.toggle()
                        setNeedsRender()
                        return
                    }
                    el.attributes["value"] = ""
                    focus = el
                    el.isFocused = true
                    setNeedsRender()
                    return
                } else if let el = node as? Element, el.tag == "button" {
                    var cursor: (any DOMNode)? = el
                    while let c = cursor {
                        if let fe = c as? Element, fe.tag == "form", fe.attributes["action"] != nil
                        {
                            await submitForm(fe)
                            return
                        }
                        cursor = c.parent
                    }
                }
                elt = node.parent
            }
        }
        setNeedsRender()
    }

    public func enterKey() async {
        guard let f = focus else { return }
        var cursor: (any DOMNode)? = f
        while let c = cursor {
            if let fe = c as? Element, fe.tag == "form", fe.attributes["action"] != nil {
                await submitForm(fe)
                return
            }
            cursor = c.parent
        }
    }

    private func submitForm(_ elt: Element) async {
        if js.dispatchEvent(type: "submit", elt: elt) { return }
        let inputs = treeToList(elt)
            .compactMap {
                $0 as? Element
            }
            .filter({
                $0.tag == "input" && $0.attributes["name"] != nil
                    && ($0.attributes["type"] != "checkbox" || $0.isChecked)
            })
        let body = inputs.map({ input -> String in
            let name =
                input.attributes["name"]!
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let value: String
            if input.attributes["type"] == "checkbox " {
                value =
                    (input.attributes["value"] ?? "on")
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            } else {
                value =
                    (input.attributes["value"] ?? "")
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            }
            return "\(name)=\(value)"
        }).joined(separator: "&")

        let action = url.resolve(elt.attributes["action"]!)
        let method = elt.attributes["method"]?.lowercased() ?? "get"

        if method == "post" {
            await load(action, payload: body)
        } else {
            await load(WebURL("\(action.toString())?\(body)"))
        }
    }

    func setNeedsRender() {
        needsStyle = true
        needsRender = true
        browser?.setNeedsAnimationFrame(self)
    }

    func setNeedsLayout() {
        needsLayout = true
        needsRender = true
        browser?.setNeedsAnimationFrame(self)
    }

    func setNeedsPaint() {
        needsPaint = true
        needsRender = true
        browser?.setNeedsAnimationFrame(self)
    }

    func setDarkMode(_ val: Bool) {
        darkMode = val
        setNeedsRender()
    }
}

private let defaultStyleSheet: [(String?, any CSSSelector, [String: String])] = {
    guard let url = Bundle.module.url(forResource: "browser", withExtension: "css"),
        let source = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return CSSParser(source).parse()
}()
