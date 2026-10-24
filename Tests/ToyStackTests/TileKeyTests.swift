import CoreGraphics
import Foundation
import Testing

@testable import Engine


@Suite
struct TileKeyTests {
    private let layer = LayerID(effect: nil, ordinal: 0)
    private let scale = 1000

    @Test func tileIndexUsesRowAndColumn() {
        #expect(TileIndex(row: 1, col: 2) == TileIndex(row: 1, col: 2))
        #expect(TileIndex(row: 1, col: 2) != TileIndex(row: 2, col: 1))
    }

    @Test func layerIDUsesEffectIdentityAndOrdinal() {
        let effectA = NSObject()
        let effectB = NSObject()
        let a = LayerID(effect: ObjectIdentifier(effectA), ordinal: 0)
        let b = LayerID(effect: ObjectIdentifier(effectA), ordinal: 0)
        let c = LayerID(effect: ObjectIdentifier(effectA), ordinal: 1)
        let d = LayerID(effect: ObjectIdentifier(effectB), ordinal: 0)
        let none = LayerID(effect: nil, ordinal: 0)

        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
        #expect(a != none)
    }

    @Test func keySetDistinguishesEveryField() {
        let index = TileIndex(row: 1, col: 2)
        let keys: Set<TileKey> = [
            TileKey(layer: layer, index: index, contentHash: 1, scale: 1000),
            TileKey(layer: layer, index: index, contentHash: 2, scale: 1000),
            TileKey(layer: layer, index: TileIndex(row: 1, col: 3), contentHash: 1, scale: 1000),
            TileKey(layer: LayerID(effect: nil, ordinal: 1), index: index, contentHash: 1, scale: 1000),
            TileKey(layer: layer, index: index, contentHash: 1, scale: 2000),
        ]
        #expect(keys.count == 5)
    }

    @Test func boundsAreNotPartOfTheKey() {
        let index = TileIndex(row: 0, col: 0)
        let a = TileKey(layer: layer, index: index, contentHash: 42, scale: scale)
        let b = TileKey(layer: layer, index: index, contentHash: 42, scale: scale)
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
    }

    @Test func sameTileHits() {
        let store = TileStore(tileSize: 128)
        let key = TileKey(
            layer: layer,
            index: TileIndex(row: 0, col: 0),
            contentHash: 7,
            scale: scale
        )
        store.insert(makeImage(), key: key)
        store.beginComposite(viewportTop: 0, viewportBottom: 128)

        #expect(kind(of: store.lookup(key)) == .hit)
        #expect(store.hits == 1)
        #expect(store.misses == 0)
        #expect(store.entryCount == 1)
    }

    @Test func missingSlotIsNew() {
        let store = TileStore(tileSize: 128)
        let key = TileKey(
            layer: layer,
            index: TileIndex(row: 0, col: 0),
            contentHash: 7,
            scale: scale
        )
        store.beginComposite(viewportTop: 0, viewportBottom: 128)

        #expect(kind(of: store.lookup(key)) == .missNew)
        #expect(store.missNew == 1)
        #expect(store.misses == 1)
    }

    @Test func changedContentInOneTileDoesNotInvalidateItsNeighbor() {
        let store = TileStore(tileSize: 128)
        let left = TileKey(
            layer: layer,
            index: TileIndex(row: 0, col: 0),
            contentHash: 11,
            scale: scale
        )
        let right = TileKey(
            layer: layer,
            index: TileIndex(row: 0, col: 1),
            contentHash: 11,
            scale: scale
        )
        store.insert(makeImage(), key: left)
        store.insert(makeImage(), key: right)
        store.beginComposite(viewportTop: 0, viewportBottom: 128)

        #expect(kind(of: store.lookup(left)) == .hit)
        #expect(kind(of: store.lookup(right)) == .hit)

        let changedRight = TileKey(
            layer: layer,
            index: right.index,
            contentHash: 12,
            scale: scale
        )
        #expect(kind(of: store.lookup(changedRight)) == .missStale)
        #expect(kind(of: store.lookup(left)) == .hit)
        #expect(store.missStale == 1)
        #expect(store.hits == 3)
        #expect(store.misses == 1)
    }

    @Test func differentLayersWithSameIndexDoNotShareTiles() {
        let store = TileStore(tileSize: 128)
        let index = TileIndex(row: 3, col: 4)
        let keyA = TileKey(
            layer: LayerID(effect: nil, ordinal: 0),
            index: index,
            contentHash: 7,
            scale: scale
        )
        let keyB = TileKey(
            layer: LayerID(effect: nil, ordinal: 1),
            index: index,
            contentHash: 7,
            scale: scale
        )
        #expect(keyA != keyB)

        store.insert(makeImage(), key: keyA)
        store.beginComposite(viewportTop: 0, viewportBottom: 128)

        #expect(kind(of: store.lookup(keyB)) == .missNew)
        #expect(store.missNew == 1)
        #expect(store.hits == 0)
    }

    @Test func scaleChangeMissesEveryTile() {
        let store = TileStore(tileSize: 128)
        let index0 = TileIndex(row: 0, col: 0)
        let index1 = TileIndex(row: 0, col: 1)
        let left = TileKey(layer: layer, index: index0, contentHash: 1, scale: 1000)
        let right = TileKey(layer: layer, index: index1, contentHash: 1, scale: 1000)
        store.insert(makeImage(), key: left)
        store.insert(makeImage(), key: right)
        store.beginComposite(viewportTop: 0, viewportBottom: 128)

        let leftAt2x = TileKey(layer: layer, index: index0, contentHash: 1, scale: 2000)
        let rightAt2x = TileKey(layer: layer, index: index1, contentHash: 1, scale: 2000)
        #expect(kind(of: store.lookup(leftAt2x)) == .missNew)
        #expect(kind(of: store.lookup(rightAt2x)) == .missNew)
        #expect(store.missNew == 2)
    }
}

private enum LookupKind: Equatable {
    case hit
    case missNew
    case missStale
    case missEvicted
}

private func kind(of result: TileStore.LookUp) -> LookupKind {
    switch result {
    case .hit: return .hit
    case .missNew: return .missNew
    case .missStale: return .missStale
    case .missEvicted: return .missEvicted
    }
}

private func makeImage() -> CGImage {
    let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}
