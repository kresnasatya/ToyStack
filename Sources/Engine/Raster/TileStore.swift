import CoreGraphics

final class TileStore: @unchecked Sendable {
    private struct Entry {
        let image: CGImage
        let pixels: Int
        var lastUsed: Int
    }

    private struct SlotKey: Hashable {
        let layer: LayerID
        let index: TileIndex
        let scale: Int
    }

    enum LookUp {
        case hit(CGImage)
        case missNew
        case missStale
        case missEvicted
    }

    private let pixelBudget: Int
    private let tileSize: CGFloat
    private var viewportTop: CGFloat = 0
    private var viewportBottom: CGFloat = 0
    private var entries: [TileKey: Entry] = [:]
    private var slots: [SlotKey: TileKey] = [:]
    private var totalPixels: Int = 0
    private var usageClock: Int = 0
    private(set) var needsMoreTiles: Bool = false
    private(set) var missNew: Int = 0
    private(set) var missStale: Int = 0
    private(set) var missEvicted: Int = 0
    var entryCount: Int { entries.count }
    var retainedPixels: Int { totalPixels }

    // For temporary debug print
    private(set) var hits: Int = 0
    private(set) var misses: Int = 0

    init(tileSize: CGFloat) {
        self.tileSize = tileSize
        self.pixelBudget = Int(64 * WIDTH * HEIGHT)
    }

    func beginComposite(viewportTop: CGFloat, viewportBottom: CGFloat) {
        self.viewportTop = viewportTop
        self.viewportBottom = viewportBottom
        hits = 0
        misses = 0
        missNew = 0
        missStale = 0
        missEvicted = 0
        needsMoreTiles = false
    }

    func markDeferred() {
        needsMoreTiles = true
    }

    func lookup(_ key: TileKey) -> LookUp {
        guard var entry = entries[key] else {
            misses += 1
            let slot = SlotKey(layer: key.layer, index: key.index, scale: key.scale)
            guard let previous = slots[slot] else {
                missNew += 1
                return .missNew
            }
            if previous.contentHash == key.contentHash {
                missEvicted += 1
                return .missEvicted
            }
            missStale += 1
            return .missStale
        }
        hits += 1
        usageClock += 1
        entry.lastUsed = usageClock
        entries[key] = entry
        return .hit(entry.image)
    }

    func insert(_ image: CGImage, key: TileKey) {
        usageClock += 1
        let pixels: Int = image.width * image.height
        if let previous = entries[key] {
            totalPixels -= previous.pixels
        }
        entries[key] = Entry(image: image, pixels: pixels, lastUsed: usageClock)
        slots[SlotKey(layer: key.layer, index: key.index, scale: key.scale)] = key
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
