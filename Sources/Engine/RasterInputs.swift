import Foundation

struct RasterInputs: @unchecked Sendable {
    let displayList: [Any]
    let scroll: CGFloat
    let interestTop: CGFloat
    let interestBottom: CGFloat
    let compositedUpdates: [ObjectIdentifier: VisualEffect]
    let previousLayes: [CompositedLayer]
    let darkMode: Bool
    let needsComposite: Bool
    let needsRaster: Bool
    let needsDraw: Bool
    let hoveredBounds: Rect?
}

struct RasterOutput: @unchecked Sendable {
    let compositedLayers: [CompositedLayer]?
    let drawList: [Any]?
}
