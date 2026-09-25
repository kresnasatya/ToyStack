import CoreGraphics

struct PaintResult {
    let displayList: [any DisplayItem]
    let compositedUpdates: [ObjectIdentifier: BrowserVisualEffect]?
    let paintEpoch: UInt
}

class CommitData {
    let scrollState: ScrollState
    let paint: PaintResult
    let preferences: ColorPreferences

    init(
        scrollState: ScrollState,
        paint: PaintResult,
        preferences: ColorPreferences
    ) {
        self.scrollState = scrollState
        self.paint = paint
        self.preferences = preferences
    }
}
