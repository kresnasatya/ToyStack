enum EasingFunction {
    case linear
    case cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double)

    static let ease: EasingFunction = cubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
    static let easeIn: EasingFunction = cubicBezier(x1: 0.42, y1: 0.0, x2: 1.0, y2: 1.0)
    static let easeOut: EasingFunction = cubicBezier(x1: 0.0, y1: 0.0, x2: 0.58, y2: 1.0)

    func apply(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .cubicBezier(let x1, let y1, let x2, let y2):
            func bezierX(_ u: Double) -> Double {
                let m = 1.0 - u
                return 3 * m * m * u * x1 + 3 * m * u * u * x2 + u * u * u
            }
            func bezierY(_ u: Double) -> Double {
                let m = 1.0 - u
                return 3 * m * m * u * y1 + 3 * m * u * u * y2 + u * u * u
            }
            func bezierXPrime(_ u: Double) -> Double {
                let m = 1.0 - u
                return 3 * m * m * x1 + 6 * m * u * (x2 - x1) + 3 * u * u * (1.0 - x2)
            }
            var u = t
            for _ in 0..<8 {
                let x = bezierX(u) - t
                if abs(x) < 1e-6 { break }
                let d = bezierXPrime(u)
                if abs(d) < 1e-6 { break }
                u -= x / d
            }
            if u < 0 || u > 1 || abs(bezierX(u) - t) > 1e-4 {
                var lo = 0.0
                var hi = 1.0
                for _ in 0..<40 {
                    let mid = (lo + hi) / 2
                    if bezierX(mid) < t { lo = mid } else { hi = mid }
                }
                u = (lo + hi) / 2
            }
            return bezierY(u)
        }
    }
}
