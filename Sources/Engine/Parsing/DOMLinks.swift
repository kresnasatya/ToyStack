import Foundation

/// Weak back-references from a DOM tree to the systems that own it.
struct DOMLinks {
    weak var layoutBox: LayoutBox?
    weak var tab: BrowserTab?

    init() {
        self.layoutBox = nil
        self.tab = nil
    }
}
