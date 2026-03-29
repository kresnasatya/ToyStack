import CoreGraphics

class CommitData {
    let url: WebURL
    let scroll: CGFloat
    let height: CGFloat
    let displayList: [Any]
    let compositedUpdates: [ObjectIdentifier: VisualEffect]
    let accessibilityTree: AccessibilityNode?
    let focus: DOMNode?

    init(
        url: WebURL, scroll: CGFloat, height: CGFloat, displayList: [Any],
        compositedUpdates: [ObjectIdentifier: VisualEffect], accessibilityTree: AccessibilityNode?,
        focus: DOMNode?
    ) {
        self.url = url
        self.scroll = scroll
        self.height = height
        self.displayList = displayList
        self.compositedUpdates = compositedUpdates
        self.accessibilityTree = accessibilityTree
        self.focus = focus
    }
}
