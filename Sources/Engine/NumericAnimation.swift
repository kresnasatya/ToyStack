enum EasingFunction {
    case linear
    case cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double)

    static let ease = cubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
    static let easeIn = cubicBezier(x1: 0.42, y1: 0.0, x2: 1.0, y2: 1.0)
    static let easeOut = cubicBezier(x1: 0.0, y1: 0.0, x2: 0.58, y2: 1.0)

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

protocol Animation: AnyObject {
    func animate() -> String?
}

class NumericAnimation: Animation {
    let oldValue: Double
    let newValue: Double
    let numFrames: Int
    let easing: EasingFunction
    private(set) var frameCount: Int = 1
    private let changePerFrame: Double

    init(oldValue: Double, newValue: Double, numFrames: Int, easing: EasingFunction = .ease) {
        self.oldValue = oldValue
        self.newValue = newValue
        self.numFrames = numFrames
        self.easing = easing
        self.changePerFrame = (newValue - oldValue) / Double(numFrames)
    }

    func animate() -> String? {
        frameCount += 1
        if frameCount > numFrames { return nil }
        let t = Double(frameCount) / Double(numFrames)
        let eased = easing.apply(t)
        let current = oldValue + (newValue - oldValue) * eased
        return String(current)
    }
}

typealias RGBColor = (r: Double, g: Double, b: Double)

class ColorAnimation: Animation {
    let oldColor: RGBColor
    let newColor: RGBColor
    let numFrames: Int
    let easing: EasingFunction
    private(set) var frameCount: Int = 1
    private let changePerFrame: RGBColor

    init(oldColor: RGBColor, newColor: RGBColor, numFrames: Int, easing: EasingFunction = .ease) {
        self.oldColor = oldColor
        self.newColor = newColor
        self.numFrames = numFrames
        self.easing = easing
        self.changePerFrame = (
            (newColor.r - oldColor.r) / Double(numFrames),
            (newColor.g - oldColor.g) / Double(numFrames),
            (newColor.b - oldColor.b) / Double(numFrames)
        )
    }

    func animate() -> String? {
        frameCount += 1
        if frameCount > numFrames { return nil }
        let t = Double(frameCount) / Double(numFrames)
        let eased = easing.apply(t)
        let r = oldColor.r + (newColor.r - oldColor.r) * eased
        let g = oldColor.g + (newColor.g - oldColor.g) * eased
        let b = oldColor.b + (newColor.b - oldColor.b) * eased
        return rgbToHex(r, g, b)
    }
}

func rgbToHex(_ r: Double, _ g: Double, _ b: Double) -> String {
    func clamp(_ v: Double) -> Int { max(0, min(255, Int(v.rounded()))) }
    return String(format: "#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
}
