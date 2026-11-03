// MARK: - TextDirectionResolver

enum TextDirectionResolver {
    private static let skippedTags: Set<String> = ["script", "style", "textarea", "bdi"]

    static func resolve(_ snapshot: StyleSnapshot, _ index: Int) -> TextDirection? {
        let content: StyleContent = snapshot.node(index).content
        let declared: String? =
            content.attributes["dir"]?.lowercased() ?? (content.tag == "bdi" ? "auto" : nil)
        switch declared {
            case "ltr": return .ltr
            case "rtl": return .rtl
            case "auto": return autoDirection(snapshot, index)
            default: return nil
        }
    }

    private static func autoDirection(_ snapshot: StyleSnapshot, _ index: Int) -> TextDirection? {
        for child in snapshot.children(of: index) {
            if let direction = autoDirection(descendant: snapshot, child) { return direction }
        }
        return nil
    }

    private static func autoDirection(descendant snapshot: StyleSnapshot, _ index: Int) -> TextDirection? {
        let content: StyleContent = snapshot.node(index).content
        if let text = content.text {
            return firstStrongDirection(in: text)
        }
        if content.tag != nil {
            if content.attributes["dir"] != nil { return nil }
            if let tag = content.tag, skippedTags.contains(tag) { return nil }
        }
        for child in snapshot.children(of: index) {
            if let direction = autoDirection(descendant: snapshot, child) { return direction }
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
