import CoreGraphics

typealias RGBColor = (r: Double, g: Double, b: Double)
typealias RGBAColor = (r: Double, g: Double, b: Double, a: Double)

public struct BrowserColor {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(cssName: String) {
        self = BrowserColor.parse(cssName) ?? BrowserColor(red: 0, green: 0, blue: 0)
    }

    public static func parse(_ css: String) -> BrowserColor? {
        guard let c: RGBAColor = cssColorToRGBA(css) else { return nil }
        return BrowserColor(red: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: c.a)
    }
}

func cssColorToRGB(_ cssName: String) -> RGBColor? {
    guard let c: RGBAColor = cssColorToRGBA(cssName) else { return nil }
    return (c.r, c.g, c.b)
}

func cssColorToRGBA(_ cssName: String) -> RGBAColor? {
    let name: String = cssName.lowercased().trimmingCharacters(in: .whitespaces)
    if name == "transparent" { return (0, 0, 0, 0) }
    if name.hasPrefix("#") { return cssHexToRGBA(name) }
    if let color: RGBAColor = cssFunctionToRGBA(name) { return color }
    if let rgb: RGBColor = namedColor(name) { return (rgb.r, rgb.g, rgb.b, 1) }
    return nil
}

// MARK: - Color parsing helpers

func namedColor(_ name: String) -> RGBColor? {
    switch name {
        case "white": return (255, 255, 255)
        case "black": return (0, 0, 0)
        case "red": return (255, 0, 0)
        case "blue": return (0, 0, 255)
        case "green": return (0, 128, 0)
        case "gray", "grey": return (128, 128, 128)
        case "orange": return (255, 165, 0)
        case "lightblue": return (173, 216, 230)
        case "lightgreen": return (144, 238, 144)
        case "steelblue": return (70, 130, 180)
        case "lightgray", "lightgrey": return (211, 211, 211)
        case "yellow": return (255, 255, 0)
        case "purple": return (128, 0, 128)
        case "salmon": return (250, 128, 114)
        case "whitesmoke": return (245, 245, 245)
        case "khaki": return (240, 230, 140)
        case "tomato": return (255, 99, 71)
        case "gold": return (255, 215, 0)
        case "orchid": return (218, 112, 214)
        default: return nil
    }
}

func cssHexToRGBA(_ name: String) -> RGBAColor? {
    let hex: String = String(name.dropFirst())
    let digits: String
    switch hex.count {
        case 3, 4: digits = hex.map { "\($0)\($0)" }.joined()
        case 6, 8: digits = hex
        default: return nil
    }
    guard let r = UInt8(digits.prefix(2), radix: 16),
        let g = UInt8(digits.dropFirst(2).prefix(2), radix: 16),
        let b = UInt(digits.dropFirst(4).prefix(2), radix: 16)
    else { return nil }
    let a: Double = digits.count == 8 ? Double(UInt8(digits.dropFirst(6).prefix(2), radix: 16) ?? 255) / 255 : 1
    return (Double(r), Double(g), Double(b), a)
}

func cssFunctionToRGBA(_ name: String) -> RGBAColor? {
    guard let open = name.firstIndex(of: "("), name.hasSuffix(")") else { return nil }
    let fn: String = String(name[name.startIndex..<open])
    let body: String = String(name[name.index(after: open)..<name.index(before: name.endIndex)])
    let parts: [String] = cssSplitColorArgs(body)
    switch fn {
        case "rgb", "rgba": return cssRGBComponents(parts)
        case "hsl", "hsla": return cssHSLComponents(parts)
        default: return nil
    }
}

func cssSplitColorArgs(_ body: String) -> [String] {
    var parts: [String] = []
    var current: String = ""
    func flush() {
        if !current.isEmpty { parts.append(current); current = "" }
    }
    for ch in body {
        if ch == "," || ch.isWhitespace {
            flush()
        } else if ch == "/" {
            flush()
            parts.append("/")
        } else {
            current.append(ch)
        }
    }
    flush()
    return parts
}

func cssRGBComponents(_ parts: [String]) -> RGBAColor? {
    var channels: [String] = parts
    var alphaToken: String? = nil
    if let slash = parts.firstIndex(of: "/") {
        channels = Array(parts[0..<slash])
        alphaToken = parts.dropFirst(slash + 1).first
    } else if parts.count == 4 {
        channels = Array(parts.prefix(3))
        alphaToken = parts[3]
    }
    guard channels.count == 3,
        let r = cssColorChannel(channels[0]),
        let g = cssColorChannel(channels[1]),
        let b = cssColorChannel(channels[2])
    else { return nil }
    return (r, g, b, alphaToken.flatMap(cssAlphaValue) ?? 1)
}

func cssColorChannel(_ token: String) -> Double? {
    if token.hasSuffix("%") {
        guard let p = Double(token.dropLast()) else { return nil }
        return max(0, min(255, p * 255 / 100))
    }
    guard let v = Double(token) else { return nil }
    return max(0, min(255, v))
}

func cssAlphaValue(_ token: String) -> Double? {
    if token.hasSuffix("%") {
        guard let p = Double(token.dropLast()) else { return nil }
        return max(0, min(1, p / 100))
    }
    guard let v = Double(token) else { return nil }
    return max(0, min(1, v))
}

func cssHSLComponents(_ parts: [String]) -> RGBAColor? {
    var channels: [String] = parts
    var alphaToken: String? = nil
    if let slash = parts.firstIndex(of: "/") {
        channels = Array(parts[0..<slash])
        alphaToken = parts.dropFirst(slash + 1).first
    } else if parts.count == 4 {
        channels = Array(parts.prefix(3))
        alphaToken = parts[3]
    }
    guard channels.count == 3,
        let h = Double(channels[0]),
        let s = cssPercentage(channels[1]),
        let l = cssPercentage(channels[2])
    else { return nil }
    let rgb: RGBColor = hslToRGB(hue: h, saturation: s / 100, lightness: l / 100)
    return (rgb.r, rgb.g, rgb.b, alphaToken.flatMap(cssAlphaValue) ?? 1)
}

func cssPercentage(_ token: String) -> Double? {
    if token.hasSuffix("%") { return Double(token.dropLast()) }
    return Double(token)
}

func hslToRGB(hue: Double, saturation: Double, lightness: Double) -> RGBColor {
    let h: Double = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
    let s: Double = max(0, min(1, saturation))
    let l: Double = max(0, min(1, lightness))
    if s == 0 {
        let v: Double = l * 255
        return (v, v, v)
    }
    let q: Double = l < 0.5 ? l * (1 + s) : l + s - l * s
    let p: Double = 2 * l - q
    func channel(_ t: Double) -> Double {
        var t: Double = t
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return (p + (q - p) * 6 * t) * 255 }
        if t < 1.0 / 2.0 { return q * 255 }
        if t < 2.0 / 3.0 { return (p + (q - p) * (2.0 / 3.0 - t) * 6) * 255 }
        return p * 255
    }
    return (channel(h + 1.0 / 3.0), channel(h), channel(h - 1.0 / 3.0))
}

func rgbToHex(_ r: Double, _ g: Double, _ b: Double) -> String {
    func clamp(_ v: Double) -> Int { max(0, min(255, Int(v.rounded()))) }
    return String(format: "#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
}

extension BrowserColor {
    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
