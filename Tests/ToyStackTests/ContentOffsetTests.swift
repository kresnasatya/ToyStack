import CoreGraphics
import Testing

@testable import Engine

@Suite
struct ContentOffsetTests {
    @Test func previewKeepsTheTopLineOfThePageInPlace() {
        let offset: ContentOffset = ContentOffset(top: 95, scroll: 1180)
        let scale: CGFloat = 577.0 / 678.0
        let origin: CGFloat = offset.origin(previewScale: scale)

        let topLine: CGFloat = origin + 1180 * scale
        let lineBelow: CGFloat = origin + (1180 + 300) * scale
        #expect(abs(topLine - 95) < 0.0001)
        #expect(abs(lineBelow - (95 + 300 * scale)) < 0.0001)
    }

    @Test func previewOfAnUnscrolledPageStartsBelowTheChrome() {
        let offset: ContentOffset = ContentOffset(top: 95, scroll: 0)
        #expect(offset.origin(previewScale: 0.5) == 95)
    }
}
