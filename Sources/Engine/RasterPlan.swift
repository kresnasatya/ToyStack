import CoreGraphics

struct RasterPlan: @unchecked Sendable {
    let commit: RasterCommit
    let batch: TileBatch
}
