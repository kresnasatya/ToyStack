import CoreGraphics

struct PaintResult {
    let displayList: [any DisplayItem]
    let compositedUpdates: [ObjectIdentifier: Engine.VisualEffect]?
    let paintEpoch: UInt
}

class CommitData {
    let scrollState: ScrollState
    let paint: PaintResult
    let theme: ThemeState

    init(
        scrollState: ScrollState,
        paint: PaintResult,
        theme: ThemeState
    ) {
        self.scrollState = scrollState
        self.paint = paint
        self.theme = theme
    }
}
