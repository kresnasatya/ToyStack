import CoreGraphics

struct InlineTextItem {
    let run: InlineTextRun
    let word: String
    let display: String?
    let fontOverride: BrowserFont?
    var measuredWidth: CGFloat? = nil
    let hasSoftHypen: Bool

    init(
        run: InlineTextRun,
        word: String,
        display: String?,
        fontOverride: BrowserFont? = nil
    ) {
        self.run = run
        self.word = word
        self.display = display
        self.fontOverride = fontOverride
        self.hasSoftHypen = inlineTextItemHasSoftHypen(word)
    }

    func withFont(_ font: BrowserFont, measuredWidthScale: CGFloat? = nil) -> InlineTextItem {
        var item: InlineTextItem = InlineTextItem(
            run: run.withFont(font),
            word: word,
            display: display,
            fontOverride: fontOverride
        )
        if let measuredWidthScale: CGFloat, let measuredWidth: CGFloat {
            item.measuredWidth = measuredWidth * measuredWidthScale
        }
        return item
    }
}

// U+00AD is `C2 AD` in UTF-8; a byte scan avoids Foundation's general
// string search on every word of every layout pass.
private func inlineTextItemHasSoftHypen(_ word: String) -> Bool {
    var previous: UInt8 = 0
    for byte in word.utf8 {
        if previous == 0xC2 && byte == 0xAD { return true }
        previous = byte
    }
    return false
}
