import CoreGraphics

struct RasterPlan: @unchecked Sendable {
    let composition: RasterComposition
    let batch: TileBatch
}
