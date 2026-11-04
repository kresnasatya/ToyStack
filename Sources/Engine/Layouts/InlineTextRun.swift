import CoreGraphics

// MARK: - InlineTextRun

struct InlineTextRun {
    let node: LayoutDOMView
    let font: BrowserFont
    let whiteSpace: WhiteSpaceMode
    let isAbbr: Bool

    func withFont(_ font: BrowserFont) -> InlineTextRun {
        return InlineTextRun(
            node: node,
            font: font,
            whiteSpace: whiteSpace,
            isAbbr: isAbbr
        )
    }
}
