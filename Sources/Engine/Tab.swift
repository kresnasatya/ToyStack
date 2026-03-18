import Combine
import Foundation

@MainActor
public class Tab: ObservableObject {

    @Published private(set) var renderVersion: Int = 0

    private(set) var url: WebURL!
    private(set) var nodes: any DOMNode = Element(tag: "html", attributes: [:], parent: nil)
    private(set) var document: DocumentLayout?
    private(set) var displayList: [any PaintCommand] = []
    public private(set) var title: String = "New Tab"

    private var scroll: CGFloat = 0
    private var tabHeight: CGFloat
    private var tabWidth: CGFloat
    private var history: [WebURL] = []
    private var historyIndex: Int = -1
    private var focus: Element?
    private var allowedOrigins: [String]?
    private var rules: [(any CSSSelector, [String: String])] = []
    private var js: JSRuntime!

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    init(tabHeight: CGFloat, tabWidth: CGFloat) {
        self.tabHeight = tabHeight
        self.tabWidth = tabWidth
    }

    func load(_ url: WebURL, payload: String? = nil) async {
        // Truncate any forward history beyond the current position
        // then record this new URL as the current entry.
        history = Array(history.prefix(historyIndex + 1))
        history.append(url)
        historyIndex = history.count - 1
        await performLoad(url, payload: payload)
    }

    private func performLoad(_ url: WebURL, payload: String? = nil) async {
        guard let (headers, body) = try? await url.request(referrer: self.url, payload: payload)
        else { return }

        scroll = 0
        self.url = url
        visitedURL.insert(url.toString())
        nodes = HTMLParser(body: body).parse()
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
            guard let (_, styleBody) = try? await styleURL.request(referrer: url) else { continue }
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
            guard let (_, scriptBody) = try? await scriptURL.request(referrer: url) else {
                continue
            }
            js.run(script: scriptURL.toString(), code: scriptBody)
        }

        render()
        if let fragment = url.fragment {
            scrollToFragment(fragment)
        }
    }

    func allowedRequest(_ url: WebURL) -> Bool {
        allowedOrigins == nil || (allowedOrigins?.contains(url.origin()) ?? false)
    }

    func render() {
        let sortedRules = rules.sorted(by: { cascadePriority($0) < cascadePriority($1) })
        precomputeHas(node: nodes, rules: sortedRules)
        applyStyle(node: nodes, rules: sortedRules)

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

        let doc = DocumentLayout(node: nodes)
        doc.layout(availableWidth: tabWidth)
        document = doc
        var list: [any PaintCommand] = []
        paintTree(doc, into: &list)
        displayList = list
        renderVersion += 1
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

    public func visibleCommands(offset: CGFloat) -> [(command: any PaintCommand, scroll: CGFloat)] {
        displayList.compactMap({ cmd in
            guard cmd.rect.top <= self.scroll + tabHeight,
                cmd.rect.bottom >= self.scroll
            else { return nil }
            return (cmd, self.scroll)
        })
    }

    public func scrollbarCommands() -> [any PaintCommand] {
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
        render()
    }

    public func scrollDown() {
        let maxY = max((document?.height ?? 0) + 2 * VSTEP - tabHeight, 0)
        scroll = min(scroll + SCROLL_STEP, maxY)
        renderVersion += 1
    }

    public func scrollUp() {
        scroll = max(scroll - SCROLL_STEP, 0)
        renderVersion += 1
    }

    func goBack() async {
        guard canGoBack else { return }
        historyIndex -= 1
        await performLoad(history[historyIndex])
    }

    func goForward() async {
        guard canGoForward else { return }
        historyIndex += 1
        await performLoad(history[historyIndex])
    }

    public func keypress(_ char: String) {
        guard let f = focus else { return }
        if js.dispatchEvent(type: "keydown", elt: f) { return }
        f.attributes["value", default: ""] += char
        render()
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
        let hits = displayList.filter({
            $0.rect.left <= x && x < $0.rect.right
                && $0.rect.top <= adjustedY && adjustedY < $0.rect.bottom
        })
        guard
            let source = hits.last(where: { sourceOf($0) != nil }).flatMap({
                sourceOf($0)
            })
        else {
            render()
            return
        }
        var elt: (any DOMNode)? = source.node
        while let node = elt {
            if node is TextNode {
                // fall through to parent
            } else if let el = node as? Element, el.tag == "a", let href = el.attributes["href"] {
                if js.dispatchEvent(type: "click", elt: el) { return }
                if href.hasPrefix("#") {
                    let resolved = url.resolve(href)
                    // Push to history without reolading the page
                    history = Array(history.prefix(historyIndex + 1))
                    history.append(resolved)
                    historyIndex = history.count - 1
                    self.url = resolved
                    scrollToFragment(String(href.dropFirst()))
                    renderVersion += 1
                } else {
                    await load(url.resolve(href))
                }
                return
            } else if let el = node as? Element, el.tag == "input" {
                if js.dispatchEvent(type: "click", elt: el) { return }
                el.attributes["value"] = ""
                focus = el
                el.isFocused = true
                render()
                return
            } else if let el = node as? Element, el.tag == "button" {
                if js.dispatchEvent(type: "click", elt: el) { return }
                var cursor: (any DOMNode)? = el
                while let c = cursor {
                    if let fe = c as? Element, fe.tag == "form", fe.attributes["action"] != nil {
                        await submitForm(fe)
                        return
                    }
                    cursor = c.parent
                }
            }
            elt = node.parent
        }
        render()
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
            })
        let body = inputs.map({ input -> String in
            let name =
                input.attributes["name"]!
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let value =
                (input.attributes["value"] ?? "")
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "\(name)=\(value)"
        }).joined(separator: "&")
        await load(url.resolve(elt.attributes["action"]!), payload: body)
    }
}

private let defaultStyleSheet: [(any CSSSelector, [String: String])] = {
    guard let url = Bundle.module.url(forResource: "browser", withExtension: "css"),
        let source = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return CSSParser(source).parse()
}()
