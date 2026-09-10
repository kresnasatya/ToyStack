import CoreGraphics

struct RasterScene {
    let displayList: [Any]
    let compositedUpdates: [ObjectIdentifier: VisualEffect]
    let previousLayers: [CompositedLayer]
    let tileStore: TileStore
}

struct RasterSettings {
    let viewport: ViewportInfo
    let theme: ThemeState
    let flags: RasterFlags
    let accessibility: AccessibilityBounds
}

struct RasterInputs: @unchecked Sendable {
    let scene: RasterScene
    let settings: RasterSettings
    let scrollState: ScrollState
}

struct RasterOutput: @unchecked Sendable {
    let compositedLayers: [CompositedLayer]?
    let drawList: [Any]?
    let contentImage: CGImage?
}
