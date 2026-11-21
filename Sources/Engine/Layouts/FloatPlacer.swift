import CoreGraphics

// MARK: - FloatPlacer

/// CSS 2.1 §9.5.1: where a float's margin box goes, given the earlier floats in
/// its block formatting context and its containing block's content edges.
struct FloatPlacer {
    let earlier: [FloatBox]
    let left: CGFloat
    let right: CGFloat

    /// `top` is where the normal flow would put the margin box. Rule 5 keeps the
    /// float no higher than any earlier float, so an earlier float is beside it
    /// exactly when it reaches below its top, whatever the float's own height.
    func origin(
        side: LayoutStyle.FloatSide,
        width: CGFloat,
        top: CGFloat,
        clear: LayoutStyle.ClearSide
    ) -> CGPoint {
        var y: CGFloat = top
        for box in earlier {
            y = max(y, box.rect.top)
            if clear.clears(box.side) {
                y = max(y, box.rect.bottom)
            }
        }
        while true {
            var leftEdge: CGFloat = left
            var rightEdge: CGFloat = right
            var nextTop: CGFloat? = nil
            for box in earlier where box.rect.bottom > y && narrows(box) {
                switch box.side {
                case .left: leftEdge = max(leftEdge, box.rect.right)
                case .right: rightEdge = min(rightEdge, box.rect.left)
                case .none: continue
                }
                nextTop = min(nextTop ?? box.rect.bottom, box.rect.bottom)
            }
            // Rules 2, 3, and 7: beside the earlier floats when it fits, below
            // them when it does not; a float with none beside it may overflow.
            guard let below: CGFloat = nextTop, rightEdge - leftEdge < width else {
                return CGPoint(x: side == .right ? rightEdge - width : leftEdge, y: y)
            }
            y = below
        }
    }

    private func narrows(_ box: FloatBox) -> Bool {
        switch box.side {
        case .left: return box.rect.right > left
        case .right: return box.rect.left < right
        case .none: return false
        }
    }
}
