import CoreGraphics
import Testing

@testable import Engine

@Suite
struct LayoutJobKeyTests {
    @Test func widthChangeInvalidatesAnInFlightLayout() {
        let key: LayoutJobKey = LayoutJobKey(width: 800, zoom: 1)
        #expect(key.isStale(currentWidth: 400, currentZoom: 1))
    }

    @Test func sameViewportStaysValid() {
        let key: LayoutJobKey = LayoutJobKey(width: 800, zoom: 1)
        #expect(!key.isStale(currentWidth: 800, currentZoom: 1))
    }

    @Test func zoomChangeInvalidatesAnInFlightLayout() {
        let key: LayoutJobKey = LayoutJobKey(width: 800, zoom: 1)
        #expect(key.isStale(currentWidth: 800, currentZoom: 2))
    }
}
