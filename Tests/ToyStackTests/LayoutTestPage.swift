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


    // MARK: - Layout ids

    func withTree(_ body: (inout LayoutTree) -> Void) {
        frame.withLayoutTree(body)
    }

    var tree: LayoutTree {
        guard var tree: LayoutTree = frame.document else {
            preconditionFailure("page has no layout tree")
        }
        return tree
    }

    func layoutID(of element: ElementRef) -> LayoutID? {
        return element.ref.layoutID
    }

    func firstLayoutID(
        in element: ElementRef,
        where predicate: (LayoutID, LayoutTree) -> Bool
    ) -> LayoutID? {
        guard var tree: LayoutTree = frame.document,
            let primary: LayoutID = element.ref.layoutID
        else { return nil }
        return treeToList(tree, primary).first(where: { predicate($0, tree) })
    }

    func firstBlockID(in element: ElementRef) -> LayoutID? {
        return firstLayoutID(in: element, where: { id, tree in tree.isBlock(id) })
    }

    func firstTextID(in element: ElementRef) -> LayoutID? {
        return firstLayoutID(in: element, where: { id, tree in tree.isText(id) })
    }

    func firstLineID(in element: ElementRef) -> LayoutID? {
        return firstLayoutID(in: element, where: { id, tree in tree.isLine(id) })
    }

    func firstEmbedID(in element: ElementRef) -> LayoutID? {
        return firstLayoutID(in: element, where: { id, tree in tree.isEmbed(id) })
    }

    func embedID(in element: ElementRef, _ match: EmbedMatch) -> LayoutID? {
        return firstLayoutID(in: element, where: { id, tree in
            guard tree.isEmbed(id) else { return false }
            return match.matches(tree.embedData(id))
        })
    }

    func lineIDs(in element: ElementRef) -> [LayoutID] {
        guard let block: LayoutID = firstBlockID(in: element) else {
            return []
        }
        return tree.childrenIDs(of: block).filter({ tree.isLine($0) })
    }

    func textWidthID(in element: ElementRef) -> CGFloat {
        guard let tree: LayoutTree = frame.document,
            let block: LayoutID = firstBlockID(in: element)
        else { return 0 }
        let lines: [LayoutID] = tree.childrenIDs(of: block).filter({ tree.isLine($0) })
        let fromBoxes: CGFloat = lines.reduce(0) { total, line in
            total + tree.lineData(line).content.boxes.reduce(0) { $0 + $1.geometry.width }
        }
        if fromBoxes > 0 { return fromBoxes }
        return treeToList(tree, block)
            .filter({ tree.isText($0) })
            .reduce(0, { $0 + tree.textData($1).metrics.width })
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
