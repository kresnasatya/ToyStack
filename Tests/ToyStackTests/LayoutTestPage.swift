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

    func firstLayout<T: LayoutObject>(_ type: T.Type, in element: Element) -> T? {
        guard let object: any LayoutObject = element.layoutObject else { return nil }
        return treeToList(object).compactMap({ $0 as? T }).first
    }

    func lines(in element: Element) -> [LineLayout] {
        guard let block: BlockLayout = element.layoutObject as? BlockLayout else {
            return []
        }
        return block.children.compactMap({ $0 as? LineLayout })
    }

    func textWidth(in element: Element) -> CGFloat {
        guard let object: any LayoutObject = element.layoutObject else { return 0 }
        let total: CGFloat = treeToList(object)
            .compactMap({ $0 as? TextLayout })
            .reduce(0, { $0 + $1.textWidth })
        return total
    }
}
