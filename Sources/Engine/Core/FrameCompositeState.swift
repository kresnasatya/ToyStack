import Foundation

/// Animated effect updates that can avoid a full composite.
struct FrameCompositeState: Sendable {
    var updates: [NodeID: EffectUpdate]
    var isNeeded: Bool
    var isNeededForPaint: Bool

    init() {
        self.updates = [:]
        self.isNeeded = false
        self.isNeededForPaint = false
    }
}
