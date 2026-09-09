import CoreGraphics

struct RasterInputs: @unchecked Sendable {
    let displayList: [Any]
    let scroll: CGFloat
    let interestTop: CGFloat
    let interestBottom: CGFloat
    let windowSize: CGSize
    let topInset: CGFloat
    let docHeight: CGFloat
    let maxScroll: CGFloat
    let compositedUpdates: [ObjectIdentifier: VisualEffect]
    let previousLayes: [CompositedLayer]
    let tileStore: TileStore
    let displayScale: CGFloat
    let prefersDark: Bool
    let forcedColors: Bool
    let needsComposite: Bool
    let needsRaster: Bool
    let needsDraw: Bool
    let hoveredBounds: Rect?
    let readBounds: Rect?
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
    let prefersDark: Bool
    let forcedColors: Bool
    let hoveredBounds: Rect?
    let readBounds: Rect?
}
