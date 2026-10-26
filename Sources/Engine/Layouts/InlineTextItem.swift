import CoreGraphics

struct InlineTextItem {
    let run: InlineTextRun
    let word: String
    let display: String?
    let fontOverride: BrowserFont?

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
    }
}
