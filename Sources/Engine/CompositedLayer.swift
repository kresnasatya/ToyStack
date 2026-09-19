import CoreGraphics

struct RasterWindow {
    let hint: Rect
    let visible: Rect
}

final class RasterBudget {
    var remaining: UInt
    init(_ n: UInt) { remaining = n }
}

class CompositedLayer {
    struct EffectImageKey: Equatable {
        let scale: CGFloat
        let blur: CGFloat
        let bounds: Rect
    }

    var displayItems: [PaintCommand] = []
    var tiles: [TileIndex: CGImage] = [:]
    var effectImage: CGImage?
    var effectImageKey: EffectImageKey?
    private var keyCache: [TileIndex: TileKey] = [:]
    private var keyCacheScale: Int = -1
    static let tileSize: CGFloat = 128
    static let rasterCapPerComposite: UInt = 300
    var ancestorChain: [Engine.VisualEffect] = []

    func pruneTiles(keepTop: CGFloat, keepBottom: CGFloat) {
        let t: CGFloat = Self.tileSize
        tiles = tiles.filter{ index, _ in
            let top: CGFloat = CGFloat(index.row) * t
            return top + t > keepTop && top < keepBottom
        }
    }

    init(displayItem: PaintCommand) {
        self.displayItems = [displayItem]
    }

    func canMerge(_ displayItem: PaintCommand) -> Bool {
        guard displayItem.parentEffect === displayItems[0].parentEffect else {
            return false
        }
        return true
    }

    func add(_ displayItem: PaintCommand) {
        displayItems.append(displayItem)
        tiles = [:]
        effectImage = nil
        effectImageKey = nil
        keyCache = [:]
        keyCacheScale = -1
    }

    func compositedBounds() -> Rect {
        guard let first = displayItems.first else {
            return Rect(left: 0, top: 0, right: 0, bottom: 0)
        }
        return displayItems.dropFirst().reduce(first.rect) { $0.union($1.rect) }
    }

    func absoluteBounds() -> Rect {
        var rect: Rect = compositedBounds()
        var effect: VisualEffect? = displayItems.first?.parentEffect
        while let e = effect {
            rect = e.map(rect: rect)
            effect = e.parent
        }
        return rect
    }

    func raster(renderer: any Renderer) {
        let bounds: Rect = compositedBounds()
        guard bounds.right > bounds.left && bounds.bottom > bounds.top else { return }
        renderer.saveState()
        renderer.translateBy(x: -bounds.left, y: -bounds.top)
        for item in displayItems {
            item.execute(scroll: 0, renderer: renderer)
        }
        renderer.restoreState()
    }

    func rasterIfNeeded(scale: CGFloat, store: TileStore, window: RasterWindow, budget: RasterBudget) -> [TileStrip] {
        guard !displayItems.isEmpty else { return [] }
        let bounds: Rect = compositedBounds()
        let width: CGFloat = bounds.right - bounds.left
        guard width > 0, bounds.bottom > bounds.top else { return [] }

        let items: [any PaintCommand] = displayItems
        let left: CGFloat = bounds.left
        let t: CGFloat = Self.tileSize
        let firstCol: Int = max(0, Int(left / t), Int(window.hint.left / t))
        let lastCol: Int = min(Int((bounds.right - 1) / t), Int(window.hint.right / t))
        let firstRow: Int = max(0, Int(bounds.top / t), Int(window.hint.top / t))
        let lastRow: Int = min(Int((bounds.bottom - 1) / t) , Int(window.hint.bottom / t))
        guard firstCol <= lastCol, firstRow <= lastRow else { return [] }

        let scaleInt: Int = Int(scale)
        if keyCacheScale != scaleInt {
            keyCache = [:]
            keyCacheScale = scaleInt
        }

        var rowItems: [Int: [PaintCommand]] = [:]
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
            if bottom <= window.visible.top { return window.visible.top - bottom }
            if top >= window.visible.bottom { return top - window.visible.bottom }
            return 0
        }

        let sortedRows: [ClosedRange<Int>.Element] = (firstRow...lastRow).sorted { rowDistance($0) < rowDistance($1) }
        var strips: [TileStrip] = []
        for row in sortedRows {
            let rowTop: CGFloat = CGFloat(row) * t
            let strip: [any PaintCommand] = rowItems[row] ?? []
            var missing: [TileKey] = []
            for col in firstCol...lastCol {
                let colLeft: CGFloat = CGFloat(col) * t
                let colRight: CGFloat = colLeft + t
                let inside: [any PaintCommand] = strip.filter { $0.rect.left < colRight  && $0.rect.right > colLeft }
                let index: TileIndex = TileIndex(row: row, col: col)
                let key: TileKey
                if let cached = keyCache[index] {
                    key = cached
                } else {
                    key = TileKey(
                        origin: TileLayerOrigin(left: Int(left), width: Int(width)),
                        index: index,
                        contentHash: tileHash(inside),
                        scale: scaleInt
                    )
                    keyCache[index] = key
                }
                if let reused = store.image(for: key) {
                    tiles[index] = reused
                    continue
                }
                guard budget.remaining > 0 else { continue }
                budget.remaining -= 1
                missing.append(key)
            }

            if !missing.isEmpty {
                strips.append(
                    TileStrip(
                        layer: self,
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

    private func tileHash(_ inside: [PaintCommand]) -> Int {
        var hasher: Hasher = Hasher()
        for item in inside {
            hasher.combine(item.contentHash)
        }
        return hasher.finalize()
    }
}
