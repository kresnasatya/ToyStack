import CoreGraphics

// MARK: - InlineTextRun

struct InlineTextRun {
    let node: LayoutDOMView
    let font: BrowserFont
    let whiteSpace: WhiteSpaceMode
    let isAbbr: Bool
}
