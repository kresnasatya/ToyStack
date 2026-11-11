import Foundation

public struct LayerTileCache: Sendable {
    var keys: [TileIndex: TileKey]
    var scale: TileScale?

    init(scale: TileScale? = nil) {
        self.keys = [:]
        self.scale = scale
    }
}
