import CoreGraphics

final class StyleContext {
    let rules: RuleIndex
    let theme: ThemeState
    let frameWidth: CGFloat

    init(rules: RuleIndex, theme: ThemeState, frameWidth: CGFloat) {
        self.rules = rules
        self.theme = theme
        self.frameWidth = frameWidth
    }
}
