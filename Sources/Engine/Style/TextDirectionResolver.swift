// MARK: - TextDirectionResolver

enum TextDirectionResolver {
    private static let skippedTags: Set<String> = ["script", "style", "textarea", "bdi"]
    private static let hebrew: ClosedRange<UInt32> = 0x0590...0x05FF
    private static let arabic: ClosedRange<UInt32> = 0x0600...0x06FF
    private static let syriac: ClosedRange<UInt32> = 0x0700...0x074F
    private static let arabicSupplement: ClosedRange<UInt32> = 0x0750...0x077F
    private static let thaana: ClosedRange<UInt32> = 0x0780...0x07BF
    private static let nko: ClosedRange<UInt32> = 0x07C0...0x07FF
    private static let arabicExtendedA: ClosedRange<UInt32> = 0x08A0...0x08FF
    private static let hebrewPresentationForms: ClosedRange<UInt32> = 0xFB1D...0xFB4F
    private static let arabicPresentationFormsA: ClosedRange<UInt32> = 0xFB50...0xFDFF
    private static let arabicPresentationFormsB: ClosedRange<UInt32> = 0xFE70...0xFEFF

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
            case hebrew, arabic, syriac, arabicSupplement, thaana, nko, arabicExtendedA,
                hebrewPresentationForms, arabicPresentationFormsA, arabicPresentationFormsB:
                return true
            default:
                return false
        }
    }
}
