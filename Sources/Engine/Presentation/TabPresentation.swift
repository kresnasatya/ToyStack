/// Committed state one tab presents or is about to present.
struct TabPresentation {
    var display: TabDisplayState
    var scroll: ScrollState
    var render: TabRenderState
    var preferences: ColorPreferences

    static let empty: TabPresentation = TabPresentation()

    init() {
        self.display = TabDisplayState()
        self.scroll = ScrollState(scroll: 0, interestTop: 0, interestBottom: 0, maxScroll: 0)
        self.render = TabRenderState()
        self.preferences = ColorPreferences(prefersDark: false, usesForcedColors: false)
    }
}
