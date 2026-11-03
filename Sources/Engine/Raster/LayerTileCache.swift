import Foundation

/// Cached tile keys for one layer, invalidated when items or scale change.
public struct LayerTileCache: Sendable {
    var keys: [TileIndex: TileKey]
    var scale: Int

    init(scale: Int = -1) {
        self.keys = [:]
        self.scale = scale
    }
}
