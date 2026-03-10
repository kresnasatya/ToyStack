import Combine
import Foundation

@MainActor
public class Tab: ObservableObject {

    @Published private(set) var renderVersion: Int = 0

    private(set) var url: WebURL!
    private(set) var nodes: any DOMNode = Element(tag: "html", attributes: [:], parent: nil)
    private(set) var document: DocumentLayout?
    private(set) var displayList: [any PaintCommand] = []

    private var scroll: CGFloat = 0
    private let tabHeight: CGFloat
    private var history: [WebURL] = []
    private var focus: Element?
    private var allowedOrigins: [String]?
    private var rules: [(any CSSSelector, [String: String])] = []
    private var js: JSRuntime!

    init(tabHeight: CGFloat) {
        self.tabHeight = tabHeight
    }

    func load(_ url: WebURL, payload: String? = nil) async {
        guard let (headers, body) = try? await url.request(referrer: self.url, payload: payload)
        else { return }

        history.append(url)
        scroll = 0
        self.url = url
        nodes = HTMLParser(body: body).parse()
        js = JSRuntime(tab: self)

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
    }

    func allowedRequest(_ url: WebURL) -> Bool {
        allowedOrigins == nil || (allowedOrigins?.contains(url.origin()) ?? false)
    }

    func render() {
        applyStyle(
            node: nodes, rules: rules.sorted(by: { cascadePriority($0) < cascadePriority($1) }))
        let doc = DocumentLayout(node: nodes)
        doc.layout()
        document = doc
        var list: [any PaintCommand] = []
        paintTree(doc, into: &list)
        displayList = list
        renderVersion += 1
    }

    public func visibleCommands(offset: CGFloat) -> [(command: any PaintCommand, scroll: CGFloat)] {
        displayList.compactMap({ cmd in
            guard cmd.rect.top <= self.scroll + tabHeight,
                cmd.rect.bottom >= self.scroll
            else { return nil }
            return (cmd, self.scroll - offset)
        })
    }

    public func scrollDown() {
        let maxY = max((document?.height ?? 0) + 2 * VSTEP - tabHeight, 0)
        scroll = min(scroll + SCROLL_STEP, maxY)
        renderVersion += 1
    }

    func goBack() async {
        guard history.count > 1 else { return }
        history.removeLast()
        let back = history.removeLast()
        await load(back)
    }

    public func keypress(_ char: String) {
        guard let f = focus else { return }
        if js.dispatchEvent(type: "keydown", elt: f) { return }
        f.attributes["value", default: ""] += char
        render()
    }

    public func click(x: CGFloat, y: CGFloat) async {
        focus?.isFocused = false
        focus = nil

        let adjustedY = y + scroll
        guard let doc = document else {
            render()
            return
        }

        let objs = treeToList(doc).filter {
            $0.x <= x && x < $0.x + $0.width
                && $0.y <= adjustedY && adjustedY < $0.y + $0.height
        }
        guard let hit = objs.last else {
            render()
            return
        }

        var elt: (any DOMNode)? = hit.node
        while let node = elt {
            if node is TextNode {
                // fall through to parent
            } else if let el = node as? Element, el.tag == "a", let href = el.attributes["href"] {
                if js.dispatchEvent(type: "click", elt: el) { return }
                await load(url.resolve(href))
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
