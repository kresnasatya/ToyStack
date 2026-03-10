import CoreGraphics
import Testing

@testable import Engine

@Suite struct RectTests {

    // MARK: - Initialization
    @Test func initStoresEdges() {
        let r = Rect(left: 10, top: 20, right: 100, bottom: 80)
        #expect(r.left == 10)
        #expect(r.top == 20)
        #expect(r.right == 100)
        #expect(r.bottom == 80)
    }

    // MARK: - containsPoint inclusive left/top, exclusive right/bottom
    @Test func containsPointInsideRect() {
        let r = Rect(left: 0, top: 0, right: 100, bottom: 50)
        #expect(r.containsPoint(50, 25))
    }

    @Test func containsPointOnLeftEdge() {
        let r = Rect(left: 0, top: 0, right: 100, bottom: 50)
        #expect(r.containsPoint(0, 0))  // inclusive
    }

    @Test func containsPointOnRightEdge() {
        let r = Rect(left: 0, top: 0, right: 100, bottom: 50)
        #expect(!r.containsPoint(100, 25))  // exclusive
    }

    @Test func containsPointOutside() {
        let r = Rect(left: 0, top: 0, right: 100, bottom: 50)
        #expect(!r.containsPoint(200, 25))
    }

    // MARK: - cgRect (convert conversion to CoreGraphics)
    @Test func cgRectConversion() {
        let r = Rect(left: 10, top: 20, right: 60, bottom: 80)
        let cg = r.cgRect
        #expect(cg.origin.x == 10)
        #expect(cg.origin.y == 20)
        #expect(cg.size.width == 50)  // right - left
        #expect(cg.size.height == 60)  // bottom - top
    }

    // MARK: - init(cgRect:) - round trip
    @Test func initFromCGRect() {
        let cg = CGRect(x: 5, y: 15, width: 40, height: 30)
        let r = Rect(cgRect: cg)
        #expect(r.left == 5)
        #expect(r.top == 15)
        #expect(r.right == 45)  // minX + width
        #expect(r.bottom == 45)  // minY + height
    }
}
