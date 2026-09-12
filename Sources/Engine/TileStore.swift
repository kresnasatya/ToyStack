import CoreGraphics
import CoreText

struct TileLayerOrigin: Hashable {
    let left: Int
    let width: Int
}

struct TileIndex: Hashable {
    let row: Int
    let col: Int
}

struct TileKey: Hashable {
    let origin: TileLayerOrigin
    let index: TileIndex
    let contentHash: Int
    let scale: Int
}

final class TileStore: @unchecked Sendable {
    private struct Entry {
        let image: CGImage
        let pixels: Int
        var lastUsed: Int
    }

    private let pixelBudget: Int
    private let tileSize: CGFloat
    private var viewportTop: CGFloat = 0
    private var viewportBottom: CGFloat = 0
    private var entries: [TileKey: Entry] = [:]
    private var usageClock = 0
    private(set) var needsMoreTiles = false

    // For temporary debug print
    private(set) var hits = 0
    private(set) var misses = 0
    var populationDebug: String {
        let pixels = entries.values.reduce(0, { $0 + $1.pixels })
        return "store: \(entries.count) entries, \(pixels)/\(pixelBudget) px"
    }

    init(tileSize: CGFloat) {
        self.tileSize = tileSize
        self.pixelBudget = Int(64 * WIDTH * HEIGHT)
    }

    func beginComposite(viewportTop: CGFloat, viewportBottom: CGFloat) {
        self.viewportTop = viewportTop
        self.viewportBottom = viewportBottom
        hits = 0
        misses = 0
        needsMoreTiles = false
    }

    func markDeferred() {
        needsMoreTiles = true
    }

    func image(for key: TileKey) -> CGImage? {
        guard var entry = entries[key] else {
            misses += 1
            return nil
        }
        hits += 1
        usageClock += 1
        entry.lastUsed = usageClock
        entries[key] = entry
        return entry.image
    }

    func insert(_ image: CGImage, key: TileKey) {
        usageClock += 1
        entries[key] = Entry(image: image, pixels: image.width * image.height, lastUsed: usageClock)
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        var total = entries.values.reduce(0) { $0 + $1.pixels }
        guard total > pixelBudget else { return }
        let farthestFirst = entries.sorted { a, b in
            let da = distanceFromViewport(a.key)
            let db = distanceFromViewport(b.key)
            if da != db { return da > db }
            return a.value.lastUsed < b.value.lastUsed
        }
        for (key, _) in farthestFirst {
            guard total > pixelBudget, let entry = entries.removeValue(forKey: key) else { break }
            total -= entry.pixels
        }
    }

    private func distanceFromViewport(_ key: TileKey) -> CGFloat {
        let top = CGFloat(key.index.row) * tileSize
        let bottom = top + tileSize
        if bottom <= viewportTop { return viewportTop - bottom }
        if top >= viewportBottom { return top - viewportBottom }
        return 0
    }
}

extension PaintCommand {
    var contentHash: Int {
        var hasher = Hasher()
        hasher.combine(String(describing: type(of: self)))
        hasher.combine(rect.left)
        hasher.combine(rect.top)
        hasher.combine(rect.right)
        hasher.combine(rect.bottom)
        if let cmd = self as? DrawRect {
            hasher.combine(cmd.color)
        } else if let cmd = self as? DrawLine {
            hasher.combine(cmd.color)
            hasher.combine(cmd.thickness)
        } else if let cmd = self as? DrawText {
            hasher.combine(cmd.text)
            hasher.combine(cmd.color)
            hasher.combine(CTFontCopyPostScriptName(cmd.font.ctFont) as String)
            hasher.combine(CTFontGetSize(cmd.font.ctFont))
        } else if let cmd = self as? DrawOutline {
            hasher.combine(cmd.color)
            hasher.combine(cmd.thickness)
        } else if let cmd = self as? DrawRRect {
            hasher.combine(cmd.color)
            hasher.combine(cmd.radius)
        }
        return hasher.finalize()
    }
}
