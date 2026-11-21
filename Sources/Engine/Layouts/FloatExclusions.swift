import CoreGraphics

// MARK: - FloatExclusions

/// The floats beside one inline block, with the block's content edges the
/// line insets are measured from. `strut` is the band each line is checked
/// against before its own height is known.
struct FloatExclusions {
    let boxes: [FloatBox]
    let left: CGFloat
    let right: CGFloat
    let strut: CGFloat

    static let none: FloatExclusions = FloatExclusions(boxes: [], left: 0, right: 0, strut: 0)

    var isEmpty: Bool { boxes.isEmpty }

    func insets(top: CGFloat, gap: CGFloat) -> LineFloatInsets {
        var insets: LineFloatInsets = LineFloatInsets(left: 0, right: 0, gap: gap)
        for box in boxes where overlaps(box, top: top + gap) {
            switch box.side {
            case .left: insets.left = max(insets.left, box.rect.right - left)
            case .right: insets.right = max(insets.right, right - box.rect.left)
            case .none: break
            }
        }
        return insets
    }

    /// The nearest float bottom that ends the band's shortening, so a line too
    /// narrow for its first item can move down to it.
    func nextTop(after top: CGFloat) -> CGFloat? {
        var next: CGFloat? = nil
        for box in boxes where overlaps(box, top: top) && intrudes(box) {
            next = min(next ?? box.rect.bottom, box.rect.bottom)
        }
        return next
    }

    private func overlaps(_ box: FloatBox, top: CGFloat) -> Bool {
        return box.rect.bottom > top && box.rect.top < top + strut
    }

    private func intrudes(_ box: FloatBox) -> Bool {
        switch box.side {
        case .left: return box.rect.right > left
        case .right: return box.rect.left < right
        case .none: return false
        }
    }
}
