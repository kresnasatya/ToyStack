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

    @Test func restingOriginLandsOnAWholeDevicePixel() {
        let offset: ContentOffset = ContentOffset(top: 65.44921875, scroll: 1180.3)
        let origin: CGFloat = offset.devicePixelOrigin(previewScale: 1, displayScale: 2)

        #expect((origin * 2).rounded() == origin * 2)
        #expect(abs(origin - offset.origin) <= 0.25)
    }

    @Test func previewOriginLandsOnAWholeDevicePixel() {
        let offset: ContentOffset = ContentOffset(top: 65.44921875, scroll: 1180)
        let scale: CGFloat = 249.0 / 256.0
        let origin: CGFloat = offset.devicePixelOrigin(previewScale: scale, displayScale: 2)

        #expect((origin * 2).rounded() == origin * 2)
        #expect(abs(origin - offset.origin(previewScale: scale)) <= 0.25)
    }

    @Test func originAlreadyOnADevicePixelDoesNotMove() {
        let offset: ContentOffset = ContentOffset(top: 95, scroll: 1180)
        #expect(offset.devicePixelOrigin(previewScale: 1, displayScale: 2) == -1085)
    }

    @Test func unusableDisplayScaleKeepsTheExactOrigin() {
        let offset: ContentOffset = ContentOffset(top: 65.44921875, scroll: 0)
        #expect(offset.devicePixelOrigin(previewScale: 1, displayScale: 0) == 65.44921875)
    }
}
