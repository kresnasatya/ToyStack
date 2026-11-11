import Foundation

/// A cache hit changes nothing about geometry, so paint must not store it on a
/// layout node. Keys are layout ids within one frame's tree; an iframe paints
/// with its own frame's store, so ids never collide across trees.
struct PaintCacheStore: Sendable {
    private var blocks: [LayoutID: PaintCache] = [:]
    private var lines: [LayoutID: LinePaintCache] = [:]

    func block(_ id: LayoutID) -> PaintCache {
        return blocks[id] ?? PaintCache()
    }

    mutating func setBlock(_ cache: PaintCache, for id: LayoutID) {
        blocks[id] = cache
    }

    func line(_ id: LayoutID) -> LinePaintCache {
        return lines[id] ?? LinePaintCache()
    }

    mutating func setLine(_ cache: LinePaintCache, for id: LayoutID) {
        lines[id] = cache
    }

    mutating func prune(removing ids: Set<LayoutID>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            blocks.removeValue(forKey: id)
            lines.removeValue(forKey: id)
        }
    }
}
