import CoreGraphics

protocol InlineLayoutItem: LayoutObject {
    var font: BrowserFont { get }
    var inlineAscent: CGFloat { get }
    var inlineDescent: CGFloat { get }
}

extension InlineLayoutItem {
    var inlineAscent: CGFloat { font.ascent }
    var inlineDescent: CGFloat { font.ascent }
}
