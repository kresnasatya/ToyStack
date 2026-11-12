import CoreGraphics
import Testing

@testable import Engine

@Suite
struct TileScaleTests {
    @Test func roundingNoiseKeepsTheSameScale() {
        let zoomed: CGFloat = 2 * 1.1
        #expect(TileScale(zoomed) == TileScale(2.2))
        #expect(TileScale(1.9999999) == TileScale(2))
    }

    @Test func oneThousandthApartIsADifferentScale() {
        #expect(TileScale(1) != TileScale(1.001))
    }
}
