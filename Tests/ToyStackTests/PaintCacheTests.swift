import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite
struct PaintCacheTests {
    private let key = PaintKey(width: 100, height: 20, epoch: 7)

    @Test func relativeStoreAppendsAtNewOrigin() throws {
        var cache = PaintCache()
        let original = DrawRect(
            rect: Rect(left: 10, top: 10, right: 110, bottom: 30),
            color: "red"
        )
        cache.store(items: [original], key: key, origin: Point(x: 10, y: 10))
        #expect(cache.canReuse(key: key))

        var displayList: [any DisplayItem] = []
        cache.append(to: &displayList, origin: Point(x: 50, y: 30))

        #expect(displayList.count == 1)
        let draw = try #require(displayList.first as? DrawRect)
        #expect(draw.rect == Rect(left: 50, top: 30, right: 150, bottom: 50))
        #expect(draw.color == "red")
    }

    @Test func translationDoesNotInvalidate() throws {
        var cache = PaintCache()
        let original = DrawRect(
            rect: Rect(left: 0, top: 0, right: 100, bottom: 200),
            color: "blue"
        )
        cache.store(items: [original], key: key, origin: Point(x: 0, y: 0))
        #expect(cache.canReuse(key: key))

        var first: [any DisplayItem] = []
        cache.append(to: &first, origin: Point(x: 0, y: 100))
        var second: [any DisplayItem] = []
        cache.append(to: &second, origin: Point(x: 0, y: 200))
        #expect(cache.canReuse(key: key))

        let a = try #require(first.first as? DrawRect)
        let b = try #require(second.first as? DrawRect)
        #expect(a.rect.top == CGFloat(100))
        #expect(b.rect.top == CGFloat(200))
        #expect(a.rect.left == 0)
        #expect(b.rect.left == 0)
    }

    @Test func sizeChangeInvalidates() {
        var cache = PaintCache()
        cache.store(items: [], key: key, origin: Point(x: 0, y: 0))
        #expect(cache.canReuse(key: key))

        #expect(!cache.canReuse(key: PaintKey(width: 90, height: 20, epoch: 7)))
        #expect(!cache.canReuse(key: PaintKey(width: 100, height: 21, epoch: 7)))
    }

    @Test func epochChangeInvalidates() {
        var cache = PaintCache()
        let red = DrawRect(
            rect: Rect(left: 0, top: 0, right: 100, bottom: 20),
            color: "red"
        )
        cache.store(items: [red], key: key, origin: Point(x: 0, y: 0))
        #expect(cache.canReuse(key: key))
        #expect(!cache.canReuse(key: PaintKey(width: 100, height: 20, epoch: 8)))
    }

    @Test func hitOutputMatchesMissOutput() throws {
        let original = DrawRect(
            rect: Rect(left: 0, top: 0, right: 100, bottom: 200),
            color: "green"
        )
        var cache = PaintCache()
        cache.store(items: [original], key: key, origin: Point(x: 0, y: 0))

        var hit: [any DisplayItem] = []
        cache.append(to: &hit, origin: Point(x: 25, y: 15))
        let miss: [any DisplayItem] = [original.shifted(dx: 25, dy: 15)]

        let hitImage = try #require(renderDisplayList(hit))
        let missImage = try #require(renderDisplayList(miss))
        let hitData = try #require(hitImage.dataProvider?.data) as Data
        let missData = try #require(missImage.dataProvider?.data) as Data
        #expect(hitData == missData)
    }

    @Test func nonCommandItemRejectsCache() {
        var cache = PaintCache()
        cache.store(items: [], key: key, origin: Point(x: 0, y: 0))
        #expect(cache.canReuse(key: key))

        cache.store(
            items: [NonCommandItem(rect: Rect(left: 0, top: 0, right: 1, bottom: 1))],
            key: key,
            origin: Point(x: 0, y: 0)
        )
        #expect(!cache.canReuse(key: key))

        var displayList: [any DisplayItem] = []
        cache.append(to: &displayList, origin: Point(x: 10, y: 10))
        #expect(displayList.isEmpty)
    }

    @Test func compositedLayerIsRejected() {
        let layer = CompositedLayer(
            displayItem: DrawRect(
                rect: Rect(left: 0, top: 0, right: 100, bottom: 20),
                color: "black"
            )
        )
        let item = DrawCompositedLayer(layer: layer, visibleTop: 0, visibleBottom: 100)

        var cache = PaintCache()
        cache.store(items: [item], key: key, origin: Point(x: 0, y: 0))
        #expect(!cache.canReuse(key: key))
    }

    @Test func invalidateClearsCache() {
        var cache = PaintCache()
        cache.store(items: [], key: key, origin: Point(x: 0, y: 0))
        #expect(cache.canReuse(key: key))

        cache.invalidate()
        #expect(!cache.canReuse(key: key))

        var displayList: [any DisplayItem] = []
        cache.append(to: &displayList, origin: Point(x: 0, y: 0))
        #expect(displayList.isEmpty)
    }
}

private struct NonCommandItem: DisplayItem {
    let rect: Rect
}

private func renderDisplayList(_ items: [any DisplayItem]) -> CGImage? {
    CGRenderer.renderBitmap(size: CGSize(width: 200, height: 100), scale: 1, { renderer in
        for item in items {
            (item as? any DisplayCommand)?.execute(scroll: 0, renderer: renderer)
        }
    })
}
