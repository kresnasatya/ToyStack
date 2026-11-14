import CoreGraphics
import Testing

@testable import Engine

@Suite
struct ShownLayerTests {
    private static let frame: CGRect = CGRect(x: 0, y: 256, width: 256, height: 256)

    @Test func reusedTileKeepsTheLayerOnScreen() {
        let image: CGImage = makeTileImage()
        #expect(Self.shown(image).canStay(for: Self.placement(image), scale: 2))
    }

    @Test func redrawnTileNeedsItsOwnLayer() {
        let shown: ShownLayer = Self.shown(makeTileImage())
        #expect(!shown.canStay(for: Self.placement(makeTileImage()), scale: 2))
    }

    @Test func deferredBindIsNotAShownImage() {
        let shown: ShownLayer = ShownLayer(
            image: nil,
            frame: Self.frame,
            scale: 2,
            isVisibleWithoutEffect: true
        )
        #expect(!shown.canStay(for: Self.placement(makeTileImage()), scale: 2))
    }

    @Test func movedTileNeedsItsOwnLayer() {
        let image: CGImage = makeTileImage()
        let moved: LayerPlacement = LayerPlacement(
            key: .tile(zIndex: 0, col: 0, row: 1),
            image: image,
            frame: Self.frame.offsetBy(dx: 0, dy: 16)
        )
        #expect(!Self.shown(image).canStay(for: moved, scale: 2))
    }

    @Test func scaleChangeNeedsItsOwnLayer() {
        let image: CGImage = makeTileImage()
        #expect(!Self.shown(image).canStay(for: Self.placement(image), scale: 1))
    }

    @Test func hiddenOrEffectLayerCannotStay() {
        let image: CGImage = makeTileImage()
        let shown: ShownLayer = ShownLayer(
            image: image,
            frame: Self.frame,
            scale: 2,
            isVisibleWithoutEffect: false
        )
        #expect(!shown.canStay(for: Self.placement(image), scale: 2))
    }

    @Test func stagedEffectCannotStay() {
        let image: CGImage = makeTileImage()
        let faded: LayerPlacement = LayerPlacement(
            key: .tile(zIndex: 0, col: 0, row: 1),
            image: image,
            frame: Self.frame,
            effect: LayerEffect(opacity: 0.5)
        )
        #expect(!Self.shown(image).canStay(for: faded, scale: 2))
    }

    private static func shown(_ image: CGImage) -> ShownLayer {
        return ShownLayer(image: image, frame: frame, scale: 2, isVisibleWithoutEffect: true)
    }

    private static func placement(_ image: CGImage) -> LayerPlacement {
        return LayerPlacement(key: .tile(zIndex: 0, col: 0, row: 1), image: image, frame: frame)
    }
}

private func makeTileImage() -> CGImage {
    let context: CGContext = CGContext(
        data: nil,
        width: 4,
        height: 4,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}
