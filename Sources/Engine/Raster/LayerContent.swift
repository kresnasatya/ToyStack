import CoreGraphics

public struct LayerContent: Sendable {
    var items: [DisplayOp]
    var bounds: Rect
    var tileCache: LayerTileCache
}
