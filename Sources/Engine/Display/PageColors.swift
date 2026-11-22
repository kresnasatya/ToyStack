// MARK: - PageColors

// The colours a finished frame is drawn with: what the user prefers, and the
// background the page gave its canvas.
struct PageColors: Equatable, Sendable {
    var preferences: ColorPreferences
    var canvasBackground: BrowserColor?

    // CSS Color Adjustment 1 §3.1: forced colors replace author backgrounds. The window
    // cannot be see-through, so a page colour with alpha is laid over the default.
    var canvas: BrowserColor {
        if preferences.usesForcedColors { return BrowserColor(cssName: ForcedColor.canvas) }
        let base: BrowserColor = BrowserColor(cssName: preferences.prefersDark ? "black" : "white")
        guard let page: BrowserColor = canvasBackground else { return base }
        let a: Double = page.alpha
        return BrowserColor(
            red: page.red * a + base.red * (1 - a),
            green: page.green * a + base.green * (1 - a),
            blue: page.blue * a + base.blue * (1 - a)
        )
    }
}
