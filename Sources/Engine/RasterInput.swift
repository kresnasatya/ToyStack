import CoreGraphics

struct RasterInput: @unchecked Sendable {
    let scene: RasterScene
    let settings: RasterSettings
    let scrollState: ScrollState
}
