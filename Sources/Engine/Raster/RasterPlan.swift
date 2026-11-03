import CoreGraphics

struct RasterPlan: Sendable {
    let composition: RasterComposition
    let batch: TileBatch
}
