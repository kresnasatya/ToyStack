import CoreGraphics

// MARK: - InlineTextRun

@MainActor
struct InlineTextRun {
    let node: any DOMNode
    let font: BrowserFont
    let whiteSpace: WhiteSpaceMode
    let isAbbr: Bool
}
