import Foundation

/// Weak back-references from a DOM tree to the systems that own it.
struct DOMLinks {
    weak var layoutTree: LayoutTree?
    weak var owner: Frame?

    init() {
        self.layoutTree = nil
        self.owner = nil
    }
}
