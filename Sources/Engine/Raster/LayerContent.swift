import CoreGraphics

/// Drawing content and the cached tile-key state for one layer.
public struct LayerContent: Sendable {
    var items: [DisplayOp]
    var bounds: Rect
    var tileCache: LayerTileCache
}
