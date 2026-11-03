import CoreGraphics

@testable import Engine

@MainActor
struct LayoutTestPage {
    let tab: BrowserTab
    let frame: Frame

    init(html: String, rules: String) {
        let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 800)
        let frame: Frame = tab.rootFrame
        frame.replaceDOM(HTMLParser(body: html).parse())
        frame.setStyleRules(CSSParser(rules).parse().rules)
        frame.setNeedsRender()
        frame.render()
        self.tab = tab
        self.frame = frame
    }

    func firstElement(tag: String) -> ElementRef? {
        return treeToList(frame.nodes)
            .compactMap({ $0.element })
            .first(where: { $0.tag == tag })
    }

    func firstElement(id: String) -> ElementRef? {
        return treeToList(frame.nodes)
            .compactMap({ $0.element })
            .first(where: { $0.attributes["id"] == id })
    }

    func ref(of id: NodeID) -> DOMRef {
        return frame.dom.ref(id)
    }

    func ref(of node: ElementRef) -> DOMRef {
        return node.ref
    }

    func firstLayout(
        in element: ElementRef,
        where predicate: (LayoutRef) -> Bool
    ) -> LayoutRef? {
        guard let primary: LayoutRef = element.ref.layout else { return nil }
        return treeToList(primary).first(where: predicate)
    }

    func firstBlock(in element: ElementRef) -> LayoutRef? {
        return firstLayout(in: element, where: { $0.isBlock })
    }

    func firstText(in element: ElementRef) -> LayoutRef? {
        return firstLayout(in: element, where: { $0.isText })
    }

    func firstLine(in element: ElementRef) -> LayoutRef? {
        return firstLayout(in: element, where: { $0.isLine })
    }

    func firstEmbed(in element: ElementRef) -> LayoutRef? {
        return firstLayout(in: element, where: { $0.isEmbed })
    }

    func embed(in element: ElementRef, _ match: EmbedMatch) -> LayoutRef? {
        return firstLayout(in: element, where: {
            guard $0.isEmbed else { return false }
            return match.matches($0.embedData)
        })
    }

    func lines(in element: ElementRef) -> [LayoutRef] {
        guard let block: LayoutRef = firstBlock(in: element) else {
            return []
        }
        return block.children.filter({ $0.isLine })
    }

    func textWidth(in element: ElementRef) -> CGFloat {
        guard let primary: LayoutRef = element.ref.layout else { return 0 }
        return treeToList(primary)
            .filter({ $0.isText })
            .reduce(0, { $0 + $1.textData.metrics.width })
    }
}

// MARK: - DOMBuilder

@MainActor
final class DOMBuilder {
    let dom: DOMTree = DOMTree()

    @discardableResult
    func element(
        _ tag: String,
        _ attributes: [String: String] = [:],
        in parent: NodeID? = nil
    ) -> NodeID {
        let id: NodeID = dom.createElement(tag: tag, attributes: attributes)
        if let parent {
            dom.append(id, to: parent)
        }
        return id
    }

    @discardableResult
    func text(_ value: String, in parent: NodeID) -> NodeID {
        let id: NodeID = dom.createText(value)
        dom.append(id, to: parent)
        return id
    }
}
