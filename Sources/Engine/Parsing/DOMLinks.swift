import Foundation

struct DOMLinks {
    weak var layoutBox: LayoutBox?
    weak var tab: BrowserTab?

    init() {
        self.layoutBox = nil
        self.tab = nil
    }
}
