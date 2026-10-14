import Foundation

// MARK: - AspectRatio
struct AspectRatio {
    let ratio: Double

    init?(css: String?) {
        guard let css, let value: Double = AspectRatio.parse(css) else { return nil }
        ratio = value
    }

    init?(intrinsicWidth: Double, intrinsicHeight: Double) {
        guard intrinsicWidth > 0, intrinsicHeight > 0 else { return nil }
        ratio = intrinsicWidth / intrinsicHeight
    }

    func height(forWidth width: Double) -> Double { width / ratio }
    func width(forHeight height: Double) -> Double { height / ratio }

    private static func parse(_ css: String) -> Double? {
        var text: String = css.trimmingCharacters(in: .whitespaces)
        guard text != "auto" else { return nil }
        if text.hasPrefix("auto ") {
            text = String(text.dropFirst(4).trimmingCharacters(in: .whitespaces))
        }
        let parts: [String] = text.components(separatedBy: "/").map({ $0.trimmingCharacters(in: .whitespaces) })
        switch parts.count {
        case 1:
            guard let value = Double(parts[0]), value > 0 else { return nil }
            return value
        case 2:
            guard let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else { return nil }
            return w / h
        default:
            return nil
        }
    }
}
