// MARK: - TextDirectionResolver

enum TextDirectionResolver {
    private static let skippedTags: Set<String> = ["script", "style", "textarea", "bdi"]

    static func resolve(_ element: Element) -> TextDirection? {
        let declared: String? = element.attributes["dir"]?.lowercased() ?? (element.tag == "bdi" ? "auto" : nil)
        switch declared {
            case "ltr": return .ltr
            case "rtl": return .rtl
            case "auto": return autoDirection(of: element)
            default: return nil
        }
    }

    private static func autoDirection(of node: any DOMNode) -> TextDirection? {
        for child in node.children {
            if let direction = autoDirection(descendant: child) { return direction }
        }
        return nil
    }

    private static func autoDirection(descendant node: any DOMNode) -> TextDirection? {
        if let text = node as? TextNode {
            return firstStrongDirection(in: text.text)
        }
        if let element = node as? Element {
            if element.attributes["dir"] != nil { return nil }
            if skippedTags.contains(element.tag) { return nil }
        }
        for child in node.children {
            if let direction = autoDirection(descendant: child) { return direction }
        }
        return nil
    }

    private static func firstStrongDirection(in text: String) -> TextDirection? {
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            return isRightToLeft(scalar) ? .rtl : .ltr
        }
        return nil
    }

    private static func isRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
            case 0x0590...0x05FF, // Hebrew
                0x0600...0x06FF, // Arabic
                0x0700...0x074F, // Syriac
                0x0750...0x077F, // Arabic Supplement
                0x0780...0x07BF, // Thaana
                0x07C0...0x07FF, // NKo
                0x08A0...0x08FF, // Arabic Extended-A
                0xFB1D...0xFB4F, // Hebrew presentation forms
                0xFB50...0xFDFF, // Arabic presentation forms-A
                0xFE70...0xFEFF: // Arabic presentation forms-B
                return true
            default:
                return false
        }
    }
}
