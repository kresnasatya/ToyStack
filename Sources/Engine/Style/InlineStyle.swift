@MainActor
enum InlineStyle {
    static func set(_ elt: ElementRef, property: String, value: String) {
        var props: [String : String] = CSSParser(elt.attributes["style"] ?? "").body()
        props[property.lowercased()] = value
        elt.attributes["style"] = props.map({
            "\($0.key): \($0.value)"
        })
        .joined(separator: "; ")
    }
}
