import CoreGraphics

public struct RasterLayer: Sendable {
    var identity: LayerIdentity
    var content: LayerContent
    var effect: LayerEffectImage
    var tiles: [TileIndex: CGImage]

    static let tileSize: CGFloat = 128
    static let rasterCapPerComposite: UInt = 300

    init(
        displayItem: DisplayOp,
        firstCommandIndex: Int = -1,
        id: LayerID = LayerID(effect: nil, ordinal: 0)
    ) {
        self.identity = LayerIdentity(
            id: id,
            firstCommandIndex: firstCommandIndex,
            ancestorChain: []
        )
        self.content = LayerContent(
            items: [displayItem],
            bounds: displayItem.rect,
            tileCache: LayerTileCache()
        )
        self.effect = LayerEffectImage()
        self.tiles = [:]
    }

    /// One layer holding a whole display list: the array is shared, not copied.
    init(
        items: [DisplayOp],
        bounds: Rect,
        firstCommandIndex: Int = -1,
        id: LayerID = LayerID(effect: nil, ordinal: 0)
    ) {
        self.identity = LayerIdentity(
            id: id,
            firstCommandIndex: firstCommandIndex,
            ancestorChain: []
        )
        self.content = LayerContent(
            items: items,
            bounds: bounds,
            tileCache: LayerTileCache()
        )
        self.effect = LayerEffectImage()
        self.tiles = [:]
    }

    mutating func add(_ displayItem: DisplayOp) {
        content.items.append(displayItem)
        content.bounds = content.bounds.union(displayItem.rect)
        content.tileCache = LayerTileCache()
        effect = LayerEffectImage()
        tiles = [:]
    }

    func compositedBounds() -> Rect {
        return content.bounds
    }

    func absoluteBounds() -> Rect {
        var rect: Rect = content.bounds
        for scope in identity.ancestorChain {
            if case .transform(let translation) = scope.kind, let translation {
                rect = rect.translated(dx: translation.x, dy: translation.y)
            }
        }
        return rect
    }

    func raster(renderer: any Renderer) {
        let bounds: Rect = content.bounds
        guard bounds.right > bounds.left && bounds.bottom > bounds.top else { return }
        renderer.saveState()
        renderer.translateBy(x: -bounds.left, y: -bounds.top)
        for item in content.items {
            item.execute(renderer: renderer)
        }
        renderer.restoreState()
    }

    mutating func pruneTiles(keepTop: CGFloat, keepBottom: CGFloat) {
        guard let grid: TileGrid = content.tileCache.grid else { return }
        let t: CGFloat = grid.size
        tiles = tiles.filter { index, _ in
            let top: CGFloat = CGFloat(index.row) * t
            return top + t > keepTop && top < keepBottom
        }
    }

    mutating func rasterIfNeeded(
        index layerIndex: Int,
        grid: TileGrid,
        store: TileStore,
        region: RasterRegion,
        budget: RasterBudget
    ) -> [TileStrip] {
        guard !content.items.isEmpty else { return [] }
        tiles.removeAll(keepingCapacity: true)
        let bounds: Rect = content.bounds
        let width: CGFloat = bounds.right - bounds.left
        guard width > 0, bounds.bottom > bounds.top else { return [] }

        let items: [DisplayOp] = content.items
        let left: CGFloat = bounds.left
        let t: CGFloat = grid.size
        let firstCol: Int = max(0, Int(left / t), Int(region.hint.left / t))
        let lastCol: Int = min(Int((bounds.right - 1) / t), Int(region.hint.right / t))
        let firstRow: Int = max(0, Int(bounds.top / t), Int(region.hint.top / t))
        let lastRow: Int = min(Int((bounds.bottom - 1) / t), Int(region.hint.bottom / t))
        guard firstCol <= lastCol, firstRow <= lastRow else { return [] }

        if content.tileCache.grid != grid {
            content.tileCache = LayerTileCache(grid: grid)
        }
        let tileScale: TileScale = TileScale(grid.scale.effective)

        var rowItems: [Int: [DisplayOp]] = [:]
        for item in items {
            let first: Int = max(firstRow, Int(item.rect.top / t))
            let last: Int = min(lastRow, Int((item.rect.bottom - 1) / t))
            guard first <= last else { continue }
            for row in first...last {
                rowItems[row, default: []].append(item)
            }
        }

        func rowDistance(_ row: Int) -> CGFloat {
            let top: CGFloat = CGFloat(row) * t
            let bottom: CGFloat = top + t
            if bottom <= region.visible.top { return region.visible.top - bottom }
            if top >= region.visible.bottom { return top - region.visible.bottom }
            return 0
        }

        let sortedRows: [ClosedRange<Int>.Element] = (firstRow...lastRow).sorted { rowDistance($0) < rowDistance($1) }
        var strips: [TileStrip] = []
        for row in sortedRows {
            let rowTop: CGFloat = CGFloat(row) * t
            let strip: [DisplayOp] = rowItems[row] ?? []
            var missing: [TileKey] = []
            for col in firstCol...lastCol {
                let colLeft: CGFloat = CGFloat(col) * t
                let colRight: CGFloat = colLeft + t
                let inside: [DisplayOp] = strip.filter { $0.rect.left < colRight && $0.rect.right > colLeft }
                let index: TileIndex = TileIndex(row: row, col: col)
                let key: TileKey
                if let cached = content.tileCache.keys[index] {
                    key = cached
                } else {
                    let tileRect: Rect = Rect(
                        left: colLeft,
                        top: rowTop,
                        right: colRight,
                        bottom: rowTop + t
                    )
                    key = TileKey(
                        layer: identity.id,
                        index: index,
                        contentHash: tileHash(inside, tileRect: tileRect),
                        scale: tileScale
                    )
                    content.tileCache.keys[index] = key
                }
                switch store.lookup(key) {
                case .hit(let reused):
                    tiles[index] = reused
                    continue
                case .missNew, .missStale, .missEvicted:
                    break
                }
                guard budget.remaining > 0 else { continue }
                budget.remaining -= 1
                missing.append(key)
            }

            if !missing.isEmpty {
                strips.append(
                    TileStrip(
                        layerIndex: layerIndex,
                        bounds: Rect(
                            left: CGFloat(firstCol) * t,
                            top: rowTop,
                            right: CGFloat(lastCol + 1) * t,
                            bottom: rowTop + t
                        ),
                        items: strip,
                        tiles: missing
                    )
                )
            }
        }

        return strips
    }

    var orderedTileIndices: [TileIndex] {
        return tiles.keys.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) })
    }

    private func tileHash(_ inside: [DisplayOp], tileRect: Rect) -> Int {
        var hasher: Hasher = Hasher()
        for item in inside {
            if case .rect(let rect, let color) = item {
                hasher.combine("rect")
                hasher.combine(color)
                let visible: Rect = rect.intersect(tileRect)
                hasher.combine(visible.left)
                hasher.combine(visible.top)
                hasher.combine(visible.right)
                hasher.combine(visible.bottom)
            } else {
                hasher.combine(item.contentHash)
            }
        }
        return hasher.finalize()
    }
}
