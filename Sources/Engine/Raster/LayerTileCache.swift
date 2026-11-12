import Foundation

public struct LayerTileCache: Sendable {
    var keys: [TileIndex: TileKey]
    var grid: TileGrid?

    init(grid: TileGrid? = nil) {
        self.keys = [:]
        self.grid = grid
    }
}
