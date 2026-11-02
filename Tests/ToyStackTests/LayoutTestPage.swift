import CoreGraphics

@testable import Engine

@MainActor
struct LayoutTestPage {
    let tab: BrowserTab
    let frame: Frame

    init(html: String, rules: String) {
        let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 800)
        let frame: Frame = tab.rootFrame
        frame.nodes = HTMLParser(body: html).parse()
        frame.rules = CSSParser(rules).parse().rules
        frame.setNeedsRender()
        frame.render()
        self.tab = tab
        self.frame = frame
    }

    func firstElement(tag: String) -> Element? {
        return treeToList(frame.nodes)
            .compactMap({ $0 as? Element })
            .first(where: { $0.tag == tag })
    }

    func firstElement(id: String) -> Element? {
        return treeToList(frame.nodes)
            .compactMap({ $0 as? Element })
            .first(where: { $0.attributes["id"] == id })
    }

    func ref(of node: any DOMNode) -> DOMRef {
        return frame.dom.ref(node)
    }

    func firstLayout(
        in element: Element,
        where predicate: (LayoutRef) -> Bool
    ) -> LayoutRef? {
        guard let primary: LayoutRef = frame.dom.ref(element).layout else { return nil }
        return treeToList(primary).first(where: predicate)
    }

    func firstBlock(in element: Element) -> LayoutRef? {
        return firstLayout(in: element, where: { $0.isBlock })
    }

    func firstText(in element: Element) -> LayoutRef? {
        return firstLayout(in: element, where: { $0.isText })
    }

    func firstLine(in element: Element) -> LayoutRef? {
        return firstLayout(in: element, where: { $0.isLine })
    }

    func firstEmbed(in element: Element) -> LayoutRef? {
        return firstLayout(in: element, where: { $0.isEmbed })
    }

    func embed(in element: Element, _ match: EmbedMatch) -> LayoutRef? {
        return firstLayout(in: element, where: {
            guard $0.isEmbed else { return false }
            return match.matches($0.embedData)
        })
    }

    func lines(in element: Element) -> [LayoutRef] {
        guard let block: LayoutRef = firstBlock(in: element) else {
            return []
        }
        return block.children.filter({ $0.isLine })
    }

    func textWidth(in element: Element) -> CGFloat {
        guard let primary: LayoutRef = frame.dom.ref(element).layout else { return 0 }
        return treeToList(primary)
            .filter({ $0.isText })
            .reduce(0, { $0 + $1.textData.metrics.width })
    }
}
