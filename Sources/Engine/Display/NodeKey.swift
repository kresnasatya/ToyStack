public struct NodeKey: Hashable {
    let raw: ObjectIdentifier

    init(_ node: any DOMNode) {
        self.raw = ObjectIdentifier(node)
    }
}
