import CoreGraphics

// MARK: - CornerRadius

struct CornerRadius: Hashable {
    var horizontal: RadiusLength
    var vertical: RadiusLength

    var isZero: Bool { horizontal.isZero && vertical.isZero }

    var px: (horizontal: CGFloat, vertical: CGFloat)? {
        guard case .px(let h) = horizontal, case .px(let v) = vertical else { return nil }
        return (h, v)
    }
}

// MARK: - CornerRadii

public struct CornerRadii: Hashable {
    var topLeft: CornerRadius
    var topRight: CornerRadius
    var bottomRight: CornerRadius
    var bottomLeft: CornerRadius

    static let zero: CornerRadii = CornerRadii.uniform(.px(0))

    static func uniform(_ length: RadiusLength) -> CornerRadii {
        let corner: CornerRadius = CornerRadius(horizontal: length, vertical: length)
        return CornerRadii(topLeft: corner, topRight: corner, bottomRight: corner, bottomLeft: corner)
    }

    var isZero: Bool {
        topLeft.isZero && topRight.isZero && bottomRight.isZero && bottomLeft.isZero
    }

    var isUniform: Bool {
        topLeft == topRight && topRight == bottomRight && bottomRight == bottomLeft
    }

    var uniformPx: (horizontal: CGFloat, vertical: CGFloat)? {
        guard isUniform, let value = topLeft.px else { return nil }
        return value
    }
}

// MARK: - The shorthand

extension CornerRadii {
    static func expanded(_ values: [RadiusLength]) -> [RadiusLength]? {
        switch values.count {
        case 1:
            return [values[0], values[0], values[0], values[0]]
        case 2:
            return [values[0], values[1], values[0], values[1]]
        case 3:
            return [values[0], values[1], values[2], values[1]]
        case 4:
            return values
        default:
            return nil
        }
    }
}

extension CornerRadii {
    init(corners: [CornerRadius]) {
        precondition(corners.count == 4, "CornerRadii needs exactly four corners")
        self.init(
            topLeft: corners[0], topRight: corners[1],
            bottomRight: corners[2], bottomLeft: corners[3]
        )
    }
}

// MARK: - Resolution

extension CornerRadii {
    func resolved(in rect: Rect) -> CornerRadii {
        let width: CGFloat = rect.right - rect.left
        let height: CGFloat = rect.bottom - rect.top
        let factor: CGFloat = overlapFactor(width: width, height: height)

        func corner(_ corner: CornerRadius) -> CornerRadius {
            CornerRadius(
                horizontal: .px(corner.horizontal.resolved(against: width) * factor),
                vertical: .px(corner.vertical.resolved(against: height) * factor)
            )
        }

        return CornerRadii(
            topLeft: corner(topLeft), topRight: corner(topRight),
            bottomRight: corner(bottomRight), bottomLeft: corner(bottomLeft)
        )
    }

    private func overlapFactor(width: CGFloat, height: CGFloat) -> CGFloat {
        let horizontal: [CGFloat] = [topLeft, topRight, bottomRight, bottomLeft].map {
            $0.horizontal.resolved(against: width)
        }
        let vertical: [CGFloat] = [topLeft, topRight, bottomRight, bottomLeft].map {
            $0.vertical.resolved(against: height)
        }
        var factor: CGFloat = 1
        for (side, sum) in [
            (width, horizontal[0] + horizontal[1]),
            (width, horizontal[3] + horizontal[2]),
            (height, vertical[0] + vertical[3]),
            (height, vertical[1] + vertical[2]),
        ] where sum > 0 {
            factor = min(factor, side / sum)
        }
        return min(1, factor)
    }
}
