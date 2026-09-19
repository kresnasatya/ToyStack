import CoreGraphics

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
    private var totalPixels: Int = 0
    private var usageClock: Int = 0
    private(set) var needsMoreTiles: Bool = false

    // For temporary debug print
    private(set) var hits: Int = 0
    private(set) var misses: Int = 0
    var populationDebug: String {
        return "store: \(entries.count) entries, \(totalPixels)/\(pixelBudget) px"
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
        let pixels: Int = image.width * image.height
        if let previous = entries[key] {
            totalPixels -= previous.pixels
        }
        entries[key] = Entry(image: image, pixels: pixels, lastUsed: usageClock)
        totalPixels += pixels
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while totalPixels > pixelBudget,
            let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            totalPixels -= oldest.value.pixels
            entries.removeValue(forKey: oldest.key)
        }
    }
}
