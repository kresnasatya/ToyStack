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

public struct TilePlacement {
    public let image: CGImage
    public let frame: CGRect
    public let zIndex: Int

    public init(image: CGImage, frame: CGRect, zIndex: Int) {
        self.image = image
        self.frame = frame
        self.zIndex = zIndex
    }
}

struct RenderedContent {
    var tiles: [TilePlacement] = []
    var image: CGImage?
    var regionTop: CGFloat = 0
    var usesTiles: Bool = false
}

struct RasterOutput: @unchecked Sendable {
    let compositedLayers: [CompositedLayer]?
    let drawList: [Any]?
    let content: RenderedContent
    let tileSignature: Int
}
