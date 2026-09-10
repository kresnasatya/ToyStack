import CoreGraphics

struct RasterInputs: @unchecked Sendable {
    let displayList: [Any]
    let scrollState: ScrollState
    let viewport: ViewportInfo
    let compositedUpdates: [ObjectIdentifier: VisualEffect]
    let previousLayes: [CompositedLayer]
    let tileStore: TileStore
    let theme: ThemeState
    let flags: RasterFlags
    let accessibility: AccessibilityBounds
}

struct RasterOutput: @unchecked Sendable {
    let compositedLayers: [CompositedLayer]?
    let drawList: [Any]?
    let contentImage: CGImage?
}

struct FrameSignature: Equatable {
    let scroll: CGFloat
    let viewport: CGSize
    let paintEpoch: Int
    let effectUpdates: Int
    let displayScale: CGFloat
    let theme: ThemeState
    let accessibility: AccessibilityBounds
}
