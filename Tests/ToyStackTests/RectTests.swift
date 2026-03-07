import XCTest

@testable import Core

final class RectTests: XCTestCase {

    // MARK: - Initialization
    func testInitStoresEdges() {
        let r = Rect(left: 10, top: 20, right: 100, bottom: 80)
        XCTAssertEqual(r.left, 10)
        XCTAssertEqual(r.top, 20)
        XCTAssertEqual(r.right, 100)
        XCTAssertEqual(r.bottom, 80)
    }

    // MARK: - containsPoint inclusive left/top, exclusive right/bottom
    func testContainsPointInsideRect() {
        let r = Rect(left: 0, top: 0, right: 100, bottom: 50)
        XCTAssertTrue(r.containsPoint(50, 25))
    }

    func testContainsPointOnLeftEdge() {
        let r = Rect(left: 0, top: 0, right: 100, bottom: 50)
        XCTAssertTrue(r.containsPoint(0, 0))  // inclusive
    }

    func testContainsPointOnRightEdge() {
        let r = Rect(left: 0, top: 0, right: 100, bottom: 50)
        XCTAssertFalse(r.containsPoint(100, 25))  // exclusive
    }

    func testContainsPointOutside() {
        let r = Rect(left: 0, top: 0, right: 100, bottom: 50)
        XCTAssertFalse(r.containsPoint(200, 25))
    }

    // MARK: - cgRect (convert conversion to CoreGraphics)
    func testCGRectConversion() {
        let r = Rect(left: 10, top: 20, right: 60, bottom: 80)
        let cg = r.cgRect
        XCTAssertEqual(cg.origin.x, 10)
        XCTAssertEqual(cg.origin.y, 20)
        XCTAssertEqual(cg.size.width, 50)  // right - left
        XCTAssertEqual(cg.size.height, 60)  // bottom - top
    }

    // MARK: - init(cgRect:) - round trip
    func testInitFromCGRect() {
        let cg = CGRect(x: 5, y: 15, width: 40, height: 30)
        let r = Rect(cgRect: cg)
        XCTAssertEqual(r.left, 5)
        XCTAssertEqual(r.top, 15)
        XCTAssertEqual(r.right, 45)  // minX + width
        XCTAssertEqual(r.bottom, 45)  // minY + height
    }
}
