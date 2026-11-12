import CoreGraphics

struct TileGrid: Equatable, Sendable {
    let scale: ContentScale

    var devicePixels: CGFloat { RasterLayer.tileSize * scale.display }

    var size: CGFloat { RasterLayer.tileSize / scale.page }

    func frame(for index: TileIndex) -> CGRect {
        return CGRect(
            x: CGFloat(index.col) * size,
            y: CGFloat(index.row) * size,
            width: size,
            height: size
        )
    }
}
