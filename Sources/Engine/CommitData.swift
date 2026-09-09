import CoreGraphics

class CommitData {
    let url: WebURL
    let scroll: CGFloat
    let height: CGFloat
    let layoutHeight: CGFloat
    let maxScroll: CGFloat
    let displayList: [Any]
    let compositedUpdates: [ObjectIdentifier: VisualEffect]?
    let accessibilityTree: AccessibilityNode?
    let focus: DOMNode?
    let interestTop: CGFloat
    let paintEpoch: Int
    let prefersDark: Bool
    let forcedColors: Bool

    init(
        url: WebURL, scroll: CGFloat, height: CGFloat, layoutHeight: CGFloat, maxScroll: CGFloat, displayList: [Any],
        compositedUpdates: [ObjectIdentifier: VisualEffect]?, accessibilityTree: AccessibilityNode?,
        focus: DOMNode?, interestTop: CGFloat, paintEpoch: Int, prefersDark: Bool, forcedColors: Bool,
    ) {
        self.url = url
        self.scroll = scroll
        self.height = height
        self.layoutHeight = layoutHeight
        self.maxScroll = maxScroll
        self.displayList = displayList
        self.compositedUpdates = compositedUpdates
        self.accessibilityTree = accessibilityTree
        self.focus = focus
        self.interestTop = interestTop
        self.paintEpoch = paintEpoch
        self.prefersDark = prefersDark
        self.forcedColors = forcedColors
    }
}
