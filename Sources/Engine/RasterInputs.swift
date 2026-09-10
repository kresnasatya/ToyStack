import CoreGraphics

struct RasterScene {
    let displayList: [Any]
    let compositedUpdates: [ObjectIdentifier: VisualEffect]
    let previousLayers: [CompositedLayer]
    let tileStore: TileStore
}

struct RasterContext {
    let viewport: ViewportInfo
    let theme: ThemeState
    let flags: RasterFlags
    let accessibility: AccessibilityBounds
}

struct RasterInputs: @unchecked Sendable {
    let scene: RasterScene
    let scrollState: ScrollState
    let context: RasterContext
}

struct RasterOutput: @unchecked Sendable {
    let compositedLayers: [CompositedLayer]?
    let drawList: [Any]?
    let contentImage: CGImage?
}

struct FrameGeometry: Equatable {
    let scroll: CGFloat
    let viewport: CGSize
    let displayScale: CGFloat
}

struct FrameEpoch: Equatable {
    let paintEpoch: Int
    let effectUpdates: Int
}

struct FrameSignature: Equatable {
    let geometry: FrameGeometry
    let epochs: FrameEpoch
    let theme: ThemeState
    let accessibility: AccessibilityBounds
}
