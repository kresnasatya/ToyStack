final class LayoutTreeHandoff: @unchecked Sendable {
    private var tree: LayoutTree?

    init(_ tree: LayoutTree) {
        self.tree = tree
    }

    func take() -> LayoutTree {
        guard let tree: LayoutTree = tree else {
            preconditionFailure("The layout tree was already taken")
        }
        self.tree = nil
        return tree
    }
}
