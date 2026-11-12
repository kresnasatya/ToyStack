import CoreGraphics

public struct ContentLayerGeometry: Equatable, Sendable {
    public let originY: CGFloat
    public let scale: CGFloat

    public init(offset: ContentOffset, frameScale: ContentScale, layerPage: CGFloat, previewScale: CGFloat) {
        let scrollScale: CGFloat = previewScale * layerPage / frameScale.page
        self.originY = offset.devicePixelOrigin(previewScale: scrollScale, displayScale: frameScale.display)
        self.scale = layerPage * previewScale
    }
}
