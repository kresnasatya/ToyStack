import Foundation

/// Weak back-references from a DOM tree to the systems that own it.
struct DOMLinks {
    weak var layoutTree: LayoutTree?
    weak var tab: BrowserTab?

    init() {
        self.layoutTree = nil
        self.tab = nil
    }
}
