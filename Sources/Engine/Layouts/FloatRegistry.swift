import CoreGraphics

// MARK: - FloatRegistry

struct FloatRegistry {
    var boxes: [LayoutID: FloatBox] = [:]
    var positioned: Set<LayoutID> = []
    var wrapped: [LayoutID: [FloatBox]] = [:]
    var anchors: [LayoutID: CGPoint] = [:]

    mutating func forget(_ removed: Set<LayoutID>) {
        guard !removed.isEmpty else { return }
        boxes = boxes.filter({ !removed.contains($0.key) })
        positioned.subtract(removed)
        wrapped = wrapped.filter({ !removed.contains($0.key) })
        anchors = anchors.filter({ !removed.contains($0.key) })
    }
}

// MARK: - FloatBox

struct FloatBox: Equatable {
    let side: LayoutStyle.FloatSide
    let rect: Rect
}
