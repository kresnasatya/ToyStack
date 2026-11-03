import CoreGraphics

struct RasterInput: Sendable {
    let scene: RasterScene
    let settings: RasterSettings
    let scrollState: ScrollState
}
