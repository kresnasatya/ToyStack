import CoreGraphics

final class StyleContext {
    let rules: RuleIndex
    let preferences: ColorPreferences
    let frameWidth: CGFloat

    init(rules: RuleIndex, preferences: ColorPreferences, frameWidth: CGFloat) {
        self.rules = rules
        self.preferences = preferences
        self.frameWidth = frameWidth
    }
}
