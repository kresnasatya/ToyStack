import CoreGraphics

struct RenderedContent {
    var placements: [PlacedLayer] = []
    var image: CGImage?
    var regionTop: CGFloat = 0
    var usesSublayers: Bool = false
}
