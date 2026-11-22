import CoreGraphics

// MARK: - FloatPlacer

/// CSS 2.1 §9.5.1: where a float's margin box goes, given the earlier floats in
/// its block formatting context and its containing block's content edges.
struct FloatPlacer {
    let earlier: [FloatBox]
    let left: CGFloat
    let right: CGFloat

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
        let found: FloatRoom = room(top: y, width: width)
        return CGPoint(x: side == .right ? found.right - width : found.left, y: found.top)
    }

    func room(top: CGFloat, width: CGFloat) -> FloatRoom {
        var y: CGFloat = top
        while true {
            var found: FloatRoom = FloatRoom(top: y, left: left, right: right)
            var nextTop: CGFloat? = nil
            for box in earlier where box.rect.bottom > y && narrows(box) {
                switch box.side {
                case .left: found.left = max(found.left, box.rect.right)
                case .right: found.right = min(found.right, box.rect.left)
                case .none: continue
                }
                nextTop = min(nextTop ?? box.rect.bottom, box.rect.bottom)
            }
            guard let below: CGFloat = nextTop, found.right - found.left < width else {
                return found
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

// MARK: - FloatRoom

struct FloatRoom: Equatable {
    var top: CGFloat
    var left: CGFloat
    var right: CGFloat
}
