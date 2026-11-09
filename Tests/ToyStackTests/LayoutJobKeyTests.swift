import CoreGraphics
import Testing

@testable import Engine

@Suite
struct LayoutJobKeyTests {
    private static let key: LayoutJobKey = LayoutJobKey(
        size: CGSize(width: 800, height: 600),
        zoom: 1,
        targetsRevision: 1
    )

    @Test func widthChangeMakesAJobStale() {
        #expect(Self.key.isStale(currentSize: CGSize(width: 400, height: 600), currentZoom: 1))
    }

    /// Height-only resizes during a pass must still be laid out after it.
    @Test func heightChangeMakesAJobStale() {
        #expect(Self.key.isStale(currentSize: CGSize(width: 800, height: 500), currentZoom: 1))
    }

    @Test func zoomChangeMakesAJobStale() {
        #expect(Self.key.isStale(currentSize: CGSize(width: 800, height: 600), currentZoom: 2))
    }

    @Test func sameViewportStaysCurrent() {
        #expect(!Self.key.isStale(currentSize: CGSize(width: 800, height: 600), currentZoom: 1))
    }
}
