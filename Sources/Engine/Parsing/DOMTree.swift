import Foundation

/// Arena of document nodes. One tree belongs to one document.
///
/// IDs are append-only: removing a subtree detaches it and never reuses the
/// ID, so a stale `NodeID` cannot point at another node. The root is always
/// `NodeID(raw: 0)`.
@MainActor
final class DOMTree {
    private(set) var nodes: [DOMNode?]
    private(set) var root: NodeID
    private(set) var revision: UInt64 = 0
    var side: DOMSideTables
    var links: DOMLinks
    weak var layoutBox: LayoutBox? {
        get { links.layoutBox }
        set { links.layoutBox = newValue }
    }

    init() {
        let root: NodeID = NodeID(raw: 0)
        let node: DOMNode = DOMNode(
            kind: .element(ElementData(tag: "html", attributes: [:], isChecked: false)),
            base: DOMBase()
        )
        self.nodes = [node]
        self.root = root
        self.side = DOMSideTables()
        self.links = DOMLinks()
    }

    // MARK: - Reads

    func node(_ id: NodeID) -> DOMNode? {
        guard id.raw < nodes.count else { return nil }
        return nodes[Int(id.raw)]
    }

    /// Walks every live node id in allocation order.
    func forEachNode(_ body: (NodeID) -> Void) {
        for index in nodes.indices where nodes[index] != nil {
            body(NodeID(raw: UInt32(index)))
        }
    }

    func isElement(_ id: NodeID) -> Bool {
        return node(id)?.element != nil
    }

    func isText(_ id: NodeID) -> Bool {
        return node(id)?.text != nil
    }

    func element(_ id: NodeID) -> ElementData? {
        return node(id)?.element
    }

    func text(_ id: NodeID) -> DOMTextData? {
        return node(id)?.text
    }

    func tag(of id: NodeID) -> String? {
        return node(id)?.tag
    }

    func parent(of id: NodeID) -> NodeID? {
        return node(id)?.base.parent
    }

    func children(of id: NodeID) -> [NodeID] {
        return node(id)?.base.children ?? []
    }

    func attributes(of id: NodeID) -> [String: String]? {
        return node(id)?.element?.attributes
    }

    func attribute(_ name: String, of id: NodeID) -> String? {
        return node(id)?.element?.attributes[name]
    }

    func isChecked(_ id: NodeID) -> Bool {
        return node(id)?.element?.isChecked ?? false
    }

    func style(of id: NodeID) -> StyleFields {
        guard let node: DOMNode = node(id) else {
            preconditionFailure("NodeID points at a missing node")
        }
        return node.base.style
    }

    func flags(of id: NodeID) -> DOMFlags {
        return node(id)?.base.state.flags ?? DOMFlags()
    }

    func animations(of id: NodeID) -> [AnimationKey: Animation] {
        return node(id)?.base.state.animations ?? [:]
    }

    func isInclusiveAncestor(_ ancestor: NodeID, of id: NodeID) -> Bool {
        var current: NodeID? = id
        while let candidate = current {
            if candidate == ancestor { return true }
            current = parent(of: candidate)
        }
        return false
    }

    // MARK: - Create

    func createElement(tag: String, attributes: [String: String]) -> NodeID {
        return allocate(
            DOMNode(
                kind: .element(ElementData(tag: tag, attributes: attributes, isChecked: false)),
                base: DOMBase()
            )
        )
    }

    func createText(_ text: String) -> NodeID {
        return allocate(
            DOMNode(kind: .text(DOMTextData(text: text)), base: DOMBase())
        )
    }

    private func allocate(_ node: DOMNode) -> NodeID {
        let id: NodeID = NodeID(raw: UInt32(nodes.count))
        nodes.append(node)
        revision += 1
        return id
    }

    // MARK: - Structure

    func append(_ child: NodeID, to parent: NodeID) {
        guard child != parent, node(child) != nil, node(parent) != nil,
            !isInclusiveAncestor(child, of: parent)
        else { return }
        detach(child)
        mutate(parent) { $0.base.children.append(child) }
        mutate(child) { $0.base.parent = parent }
    }

    func insert(_ child: NodeID, before reference: NodeID, in parent: NodeID) {
        guard child != reference, child != parent, node(child) != nil, node(parent) != nil,
            !isInclusiveAncestor(child, of: parent)
        else { return }
        detach(child)
        let index: Int? = children(of: parent).firstIndex(of: reference)
        guard let index else { return }
        mutate(parent) { $0.base.children.insert(child, at: index) }
        mutate(child) { $0.base.parent = parent }
    }

    @discardableResult
    func remove(_ child: NodeID, from parent: NodeID) -> Bool {
        guard let index: Int = children(of: parent).firstIndex(of: child) else { return false }
        mutate(parent) { $0.base.children.remove(at: index) }
        mutate(child) { $0.base.parent = nil }
        return true
    }

    func reparent(_ child: NodeID, to parent: NodeID) {
        append(child, to: parent)
    }

    func setChildren(_ children: [NodeID], of parent: NodeID) {
        guard node(parent) != nil else { return }
        for child in self.children(of: parent) {
            mutate(child) { $0.base.parent = nil }
        }
        var kept: [NodeID] = []
        kept.reserveCapacity(children.count)
        for child in children {
            guard child != parent, node(child) != nil,
                !isInclusiveAncestor(child, of: parent)
            else { continue }
            detach(child)
            if !kept.contains(child) { kept.append(child) }
        }
        mutate(parent) { $0.base.children = kept }
        for child in kept {
            mutate(child) { $0.base.parent = parent }
        }
    }

    private func detach(_ child: NodeID) {
        guard let old = parent(of: child) else { return }
        mutate(old) { $0.base.children.removeAll(where: { $0 == child }) }
        mutate(child) { $0.base.parent = nil }
    }

    // MARK: - Payload

    func setAttributes(_ attributes: [String: String], of id: NodeID) {
        mutate(id) { node in
            guard case .element(var data) = node.kind else { return }
            data.attributes = attributes
            node.kind = .element(data)
        }
    }

    func setAttribute(_ name: String, _ value: String, of id: NodeID) {
        mutate(id) { node in
            guard case .element(var data) = node.kind else { return }
            data.attributes[name] = value
            node.kind = .element(data)
        }
    }

    func setText(_ text: String, of id: NodeID) {
        mutate(id) { node in
            guard case .text(var data) = node.kind else { return }
            data.text = text
            node.kind = .text(data)
        }
    }

    func appendText(_ suffix: String, to id: NodeID) {
        mutate(id) { node in
            guard case .text(var data) = node.kind else { return }
            data.text += suffix
            node.kind = .text(data)
        }
    }

    func setChecked(_ checked: Bool, of id: NodeID) {
        mutate(id) { node in
            guard case .element(var data) = node.kind else { return }
            data.isChecked = checked
            node.kind = .element(data)
        }
    }

    // MARK: - State

    func setFlag(_ keyPath: WritableKeyPath<DOMFlags, Bool>, _ value: Bool, of id: NodeID) {
        mutate(id) { $0.base.state.flags[keyPath: keyPath] = value }
    }

    func setSatisfiedHas(_ satisfied: Set<Int>, of id: NodeID) {
        mutate(id) { $0.base.state.flags.satisfiedHas = satisfied }
    }

    func setAnimations(_ animations: [AnimationKey: Animation], of id: NodeID) {
        mutate(id) { $0.base.state.animations = animations }
    }

    func addAnimation(_ animation: Animation, key: AnimationKey, of id: NodeID) -> Bool {
        var inserted: Bool = false
        mutate(id) { node in
            if node.base.state.animations.updateValue(animation, forKey: key) == nil {
                inserted = true
            }
        }
        return inserted
    }

    @discardableResult
    func removeAnimation(_ key: AnimationKey, from id: NodeID) -> Animation? {
        var removed: Animation? = nil
        mutate(id) { node in
            removed = node.base.state.animations.removeValue(forKey: key)
        }
        return removed
    }

    // MARK: - Layout

    func ref(_ id: NodeID) -> DOMRef {
        return DOMRef(id: id, dom: self)
    }

    /// Copies one subtree from another tree into `parent`. Used by `innerHTML`,
    /// which parses into a scratch document.
    func cloneSubtree(_ source: DOMTree, _ sourceID: NodeID, into parent: NodeID) {
        guard let node: DOMNode = source.node(sourceID) else { return }
        switch node.kind {
        case .element(let data):
            let id: NodeID = createElement(tag: data.tag, attributes: data.attributes)
            setChecked(data.isChecked, of: id)
            append(id, to: parent)
            for child in source.children(of: sourceID) {
                cloneSubtree(source, child, into: id)
            }
        case .text(let data):
            append(createText(data.text), to: parent)
        }
    }

    // MARK: - Mutation helper

    private func mutate(_ id: NodeID, _ body: (inout DOMNode) -> Void) {
        guard id.raw < nodes.count, var node: DOMNode = nodes[Int(id.raw)] else { return }
        body(&node)
        nodes[Int(id.raw)] = node
        revision += 1
    }
}
