enum Easing {
    case linear
    case cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double)

    static let ease: Easing = cubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
    static let easeIn: Easing = cubicBezier(x1: 0.42, y1: 0.0, x2: 1.0, y2: 1.0)
    static let easeOut: Easing = cubicBezier(x1: 0.0, y1: 0.0, x2: 0.58, y2: 1.0)
    static let easeInOut: Easing = cubicBezier(x1: 0.42, y1: 0.0, x2: 0.58, y2: 1.0)

    func apply(_ progress: Double) -> Double {
        switch self {
        case .linear:
            return progress
        case .cubicBezier(let x1, let y1, let x2, let y2):
            func bezierX(_ u: Double) -> Double {
                let m: Double = 1.0 - u
                return 3 * m * m * u * x1 + 3 * m * u * u * x2 + u * u * u
            }
            func bezierY(_ u: Double) -> Double {
                let m: Double = 1.0 - u
                return 3 * m * m * u * y1 + 3 * m * u * u * y2 + u * u * u
            }
            func bezierXPrime(_ u: Double) -> Double {
                let m: Double = 1.0 - u
                return 3 * m * m * x1 + 6 * m * u * (x2 - x1) + 3 * u * u * (1.0 - x2)
            }
            var u: Double = progress
            for _ in 0..<8 {
                let x: Double = bezierX(u) - progress
                if abs(x) < 1e-6 { break }
                let d: Double = bezierXPrime(u)
                if abs(d) < 1e-6 { break }
                u -= x / d
            }
            if u < 0 || u > 1 || abs(bezierX(u) - progress) > 1e-4 {
                var lo: Double = 0.0
                var hi: Double = 1.0
                for _ in 0..<40 {
                    let mid: Double = (lo + hi) / 2
                    if bezierX(mid) < progress { lo = mid } else { hi = mid }
                }
                u = (lo + hi) / 2
            }
            return bezierY(u)
        }
    }

    static func parse(_ value: String) -> Easing {
        parseIfValid(value) ?? .ease
    }

    static func parseIfValid(_ value: String) -> Easing? {
        switch value {
        case "linear": return .linear
        case "ease": return .ease
        case "ease-in": return .easeIn
        case "ease-out": return .easeOut
        case "ease-in-out": return .easeInOut
        default:
            if value.hasPrefix("cubic-bezier(") && value.hasSuffix(")") {
                let inner: Substring.SubSequence = value.dropFirst("cubic-bezier(".count).dropLast()
                let nums: [Double] = inner.split(separator: ",")
                    .compactMap({ Double($0.trimmingCharacters(in: .whitespaces)) })
                if nums.count == 4 {
                    return .cubicBezier(x1: nums[0], y1: nums[1], x2: nums[2], y2: nums[3])
                }
            }
            return nil
        }
    }

}
