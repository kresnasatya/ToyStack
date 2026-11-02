import CoreGraphics

// MARK: - InlineTextRun

@MainActor
struct InlineTextRun {
    let node: DOMRef
    let font: BrowserFont
    let whiteSpace: WhiteSpaceMode
    let isAbbr: Bool
}
