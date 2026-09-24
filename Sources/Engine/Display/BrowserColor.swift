typealias RGBColor = (r: Double, g: Double, b: Double)

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
        let name: String = cssName.lowercased().trimmingCharacters(in: .whitespaces)
        if name == "transparent" {
            self = BrowserColor(red: 0, green: 0, blue: 0, alpha: 0)
            return
        }
        if let rgb = cssColorToRGB(name) {
            self = BrowserColor(red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255)
        } else {
            self = BrowserColor(red: 0, green: 0, blue: 0)
        }
    }
}

func cssColorToRGB(_ cssName: String) -> RGBColor? {
    let name: String = cssName.lowercased().trimmingCharacters(in: .whitespaces)
    if name.hasPrefix("#") {
        let hex: String = String(name.dropFirst())
        let expanded: String = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
        if expanded.count == 6,
            let r = UInt8(expanded.prefix(2), radix: 16),
            let g = UInt8(expanded.dropFirst(2).prefix(2), radix: 16),
            let b = UInt(expanded.dropFirst(4).prefix(2), radix: 16)
        {
            return (Double(r), Double(g), Double(b))
        }
    }

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

func rgbToHex(_ r: Double, _ g: Double, _ b: Double) -> String {
    func clamp(_ v: Double) -> Int { max(0, min(255, Int(v.rounded()))) }
    return String(format: "#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
}
