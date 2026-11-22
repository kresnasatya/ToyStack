struct TabPresentation {
    var display: TabDisplayState
    var scroll: ScrollState
    var render: TabRenderState
    var colors: PageColors

    static let empty: TabPresentation = TabPresentation()

    init() {
        self.display = TabDisplayState()
        self.scroll = ScrollState(scroll: 0, interestTop: 0, interestBottom: 0, maxScroll: 0)
        self.render = TabRenderState()
        self.colors = PageColors(
            preferences: ColorPreferences(prefersDark: false, usesForcedColors: false),
            canvasBackground: nil
        )
    }
}
