import CoreGraphics

// MARK: - FloatExclusions

struct FloatExclusions {
    let boxes: [FloatBox]
    let left: CGFloat
    let right: CGFloat
    let strut: CGFloat

    static let none: FloatExclusions = FloatExclusions(boxes: [], left: 0, right: 0, strut: 0)

    var isEmpty: Bool { boxes.isEmpty }

    func adding(_ box: FloatBox) -> FloatExclusions {
        return FloatExclusions(boxes: boxes + [box], left: left, right: right, strut: strut)
    }

    func insets(top: CGFloat, gap: CGFloat, height: CGFloat) -> LineFloatInsets {
        var insets: LineFloatInsets = LineFloatInsets(left: 0, right: 0, gap: gap)
        for box in boxes where overlaps(box, top: top + gap, height: height) {
            switch box.side {
            case .left: insets.left = max(insets.left, box.rect.right - left)
            case .right: insets.right = max(insets.right, right - box.rect.left)
            case .none: break
            }
        }
        return insets
    }

    func nextTop(after top: CGFloat, height: CGFloat) -> CGFloat? {
        var next: CGFloat? = nil
        for box in boxes where overlaps(box, top: top, height: height) && intrudes(box) {
            next = min(next ?? box.rect.bottom, box.rect.bottom)
        }
        return next
    }

    private func overlaps(_ box: FloatBox, top: CGFloat, height: CGFloat) -> Bool {
        return box.rect.bottom > top && box.rect.top < top + max(strut, height)
    }

    private func intrudes(_ box: FloatBox) -> Bool {
        switch box.side {
        case .left: return box.rect.right > left
        case .right: return box.rect.left < right
        case .none: return false
        }
    }
}
