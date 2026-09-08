import CoreGraphics

struct TileIndex: Hashable {
    let row: Int
    let col: Int
}

final class RasterBudget {
    var remaining: Int
    init(_ n: Int) { remaining = n }
}

class CompositedLayer {
    var displayItems: [PaintCommand] = []
    static let shortDisplayListLimit = 3
    var tiles: [TileIndex: CGImage] = [:]
    static let tileSize: CGFloat = 128
    static let rasterCapPerComposite = 300
    var ancestorChain: [VisualEffect] = []
    var needsTexture: Bool {
        displayItems.count >= Self.shortDisplayListLimit
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
    }

    func compositedBounds() -> Rect {
        guard let first = displayItems.first else {
            return Rect(left: 0, top: 0, right: 0, bottom: 0)
        }
        return displayItems.dropFirst().reduce(first.rect) { $0.union($1.rect) }
    }

    func absoluteBounds() -> Rect {
        var rect = compositedBounds()
        var effect: VisualEffect? = displayItems.first?.parentEffect
        while let e = effect {
            rect = e.map(rect: rect)
            effect = e.parent
        }
        return rect
    }

    func raster(renderer: any Renderer) {
        let bounds = compositedBounds()
        guard bounds.right > bounds.left && bounds.bottom > bounds.top else { return }
        renderer.saveState()
        renderer.translateBy(x: -bounds.left, y: -bounds.top)
        for item in displayItems {
            item.execute(scroll: 0, renderer: renderer)
        }
        renderer.restoreState()
    }

    func rasterIfNeeded(scale: CGFloat, store: TileStore, hintTop: CGFloat, hintBottom: CGFloat, visibleTop: CGFloat, visibleBottom: CGFloat, budget: RasterBudget) {
        guard needsTexture else { return }
        let bounds = compositedBounds()
        let width = bounds.right - bounds.left
        guard width > 0, bounds.bottom > bounds.top else { return }

        let items = displayItems
        let left = bounds.left
        let t = Self.tileSize
        let firstCol = max(0, Int(left / t))
        let lastCol = Int((bounds.right - 1) / t)
        let firstRow = max(0, Int(bounds.top / t), Int(hintTop / t))
        let lastRow = min(Int((bounds.bottom - 1) / t) , Int(hintBottom / t))
        guard firstCol <= lastCol, firstRow <= lastRow else { return }

        var rowItems: [Int: [PaintCommand]] = [:]
        for item in items {
            let first = max(firstRow, Int(item.rect.top / t))
            let last = min(lastRow, Int((item.rect.bottom - 1) / t))
            guard first <= last else { continue }
            for row in first...last {
                rowItems[row, default: []].append(item)
            }
        }

        func rowDistance(_ row: Int) -> CGFloat {
            let top = CGFloat(row) * t
            let bottom = top + t
            if bottom <= visibleTop { return visibleTop - bottom }
            if top >= visibleBottom { return top - visibleBottom }
            return 0
        }

        let sortedRows = (firstRow...lastRow).sorted { rowDistance($0) < rowDistance($1) }

        for row in sortedRows {
            let rowTop = CGFloat(row) * t
            let strip = rowItems[row] ?? []
            for col in firstCol...lastCol {
                let colLeft = CGFloat(col) * t
                let colRight = colLeft + t
                let inside = strip.filter { $0.rect.left < colRight  && $0.rect.right > colLeft }
                let index = TileIndex(row: row, col: col)
                let key = TileKey(
                    x: Int(left), width: Int(width),
                    col: col, row: row,
                    contentHash: tileHash(inside), scale: Int(scale)
                )
                if let reused = store.image(for: key) {
                    tiles[index] = reused
                    continue
                }
                guard budget.remaining > 0 else { continue }
                budget.remaining -= 1
                let image = CGRenderer.renderBitmap(width: t, height: t, scale: scale, { r in
                    r.translateBy(x: -colLeft, y: -rowTop)
                    for item in inside {
                        item.execute(scroll: 0, renderer: r)
                    }
                })
                if let image {
                    tiles[index] = image
                    store.insert(image, key: key)
                }
            }
        }
    }

    private func tileHash(_ inside: [PaintCommand]) -> Int {
        var hasher = Hasher()
        for item in inside {
            hasher.combine(item.contentHash)
        }
        return hasher.finalize()
    }
}
