import Foundation

// RFC 3492 §6.3: turns one label of a domain name into the ASCII-only form
// DNS can carry. The caller adds the "xn--" prefix (RFC 3490 §5).
enum Punycode {
    private static let base: Int = 36
    private static let tMin: Int = 1
    private static let tMax: Int = 26
    private static let skew: Int = 38
    private static let damp: Int = 700
    private static let initialBias: Int = 72
    private static let initialN: Int = 128

    static func encode(_ label: String) -> String {
        let input: [Int] = label.unicodeScalars.map({ (scalar: Unicode.Scalar) -> Int in Int(scalar.value) })
        var output: String = String(label.unicodeScalars.filter({ (scalar: Unicode.Scalar) -> Bool in scalar.isASCII }))
        let basicCount: Int = output.unicodeScalars.count
        if basicCount > 0 {
            output.append("-")
        }
        var handled: Int = basicCount
        var n: Int = initialN
        var delta: Int = 0
        var bias: Int = initialBias
        while handled < input.count {
            let next: Int = input.filter({ (code: Int) -> Bool in code >= n }).min() ?? n
            delta += (next - n) * (handled + 1)
            n = next
            for code: Int in input {
                if code < n {
                    delta += 1
                }
                guard code == n else { continue }
                output += variableLengthDigits(delta, bias: bias)
                bias = adapt(delta, points: handled + 1, isFirst: handled == basicCount)
                delta = 0
                handled += 1
            }
            delta += 1
            n += 1
        }
        return output
    }

    private static func variableLengthDigits(_ value: Int, bias: Int) -> String {
        var digits: String = ""
        var q: Int = value
        var k: Int = base
        while true {
            let threshold: Int = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
            if q < threshold {
                break
            }
            digits.append(digit(threshold + (q - threshold) % (base - threshold)))
            q = (q - threshold) / (base - threshold)
            k += base
        }
        digits.append(digit(q))
        return digits
    }

    private static func adapt(_ delta: Int, points: Int, isFirst: Bool) -> Int {
        var scaled: Int = isFirst ? delta / damp : delta / 2
        scaled += scaled / points
        var k: Int = 0
        while scaled > ((base - tMin) * tMax) / 2 {
            scaled /= base - tMin
            k += base
        }
        return k + ((base - tMin + 1) * scaled) / (scaled + skew)
    }

    private static func digit(_ value: Int) -> Character {
        let scalar: UInt32 = value < 26 ? UInt32(97 + value) : UInt32(22 + value)
        return Character(Unicode.Scalar(scalar) ?? "a")
    }
}
